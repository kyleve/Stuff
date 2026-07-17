import WhereCore

/// The process-wide handoff of the intent layer's `WhereServices`.
///
/// Every App Intent resolves its services through `current()`. App Intents are
/// instantiated by the system, so this is the one static seam the layer needs
/// — but it never *creates* services (or a store) itself: the app's
/// composition root derives a store-sharing stack from the launch's services
/// (`WhereServices.forIntents(sharingStoreOf:)`, wired through
/// `WhereLaunch.makeLauncher`'s `onServicesReady` hook) and hands it to
/// `install(_:)`. That makes the launch's `open-store` step the process's
/// *only* store open — an intent can never race it with a second container
/// over the same store file (the fresh-install creation race), and an intent
/// write pings the same `changes()` signal the running UI refreshes from.
///
/// An intent that fires before the launch has installed the stack (e.g. a
/// Siri invocation racing app startup, or a launch parked in its failure
/// state) **suspends** in `current()` until installation lands — it does not
/// fall back to opening its own store. The wait honors task cancellation, and
/// the system's intent time limit bounds it if the launch never recovers.
///
/// Installation re-fires on every session (re)start — retry after a failed
/// launch, the reset relaunch — replacing the cached stack, so intents always
/// ride the current session's store instance.
public actor IntentServices {
    public static let shared = IntentServices()

    private var installed: WhereServices?

    /// Intents parked in `current()` awaiting installation, keyed so a
    /// cancelled waiter can remove exactly itself.
    private var waiters: [Int: CheckedContinuation<WhereServices, any Error>] = [:]
    private var nextWaiterID = 0

    init() {}

    /// Install the store-sharing stack the app's composition root derived from
    /// the launch's services, resuming any parked intents. Idempotent per
    /// stack; a later install (a fresh session after reset) replaces the
    /// cached one.
    public func install(_ services: WhereServices) {
        installed = services
        let parked = waiters
        waiters = [:]
        for continuation in parked.values {
            continuation.resume(returning: services)
        }
    }

    /// The installed stack, suspending until the launch installs one. Throws
    /// only `CancellationError`, when the awaiting intent's task is cancelled
    /// while parked.
    func current() async throws -> WhereServices {
        if let installed {
            return installed
        }
        let id = nextWaiterID
        nextWaiterID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // The handler below may have already run (cancellation raced
                // the park); resume immediately rather than parking a waiter
                // nobody will clean up.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: Int) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }

    #if DEBUG
        /// Test probe: how many intents are parked awaiting installation, so a
        /// test can wait for the park (a condition, not a timing guess) before
        /// installing or cancelling.
        var waiterCount: Int {
            waiters.count
        }
    #endif
}
