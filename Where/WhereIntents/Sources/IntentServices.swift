import PeriscopeCore
import WhereCore

/// The handoff of the intent layer's `WhereServices`.
///
/// The app's composition root (`AppDelegate`) **owns the one instance** and
/// registers it with the App Intents framework's dependency container
/// (`AppDependencyManager`); every App Intent and entity query resolves it
/// with `@Dependency` and calls `current()` — there is no singleton of ours.
/// The handoff never *creates* services (or a store) itself: the launch
/// derives a store-sharing stack from its services
/// (`WhereServices.forIntents(sharingStoreOf:)`, wired through
/// `WhereLaunch.makeLauncher`'s `onServicesReady` hook) and hands it to
/// `install(_:)`. That makes the launch's `resolve-scope` step the process's
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
    /// The store-sharing services and presentation identity resolved together.
    struct Context {
        let services: WhereServices
        let theme: WhereTheme
    }

    private var installed: Context?

    /// Intents parked in `current()` awaiting installation, keyed so a
    /// cancelled waiter can remove exactly itself.
    private var waiters: [Int: CheckedContinuation<Context, any Error>] = [:]
    private var nextWaiterID = 0

    /// Create the instance the composition root owns (and tests build
    /// per-test); the app registers it with `AppDependencyManager` in
    /// `didFinishLaunching`, before the system can deliver an intent.
    public init() {}

    /// Install the store-sharing stack the app's composition root derived from
    /// the launch's services, resuming any parked intents. Idempotent per
    /// stack; a later install (a fresh session after reset) replaces the
    /// cached one.
    public func install(_ services: WhereServices, theme: WhereTheme) {
        let context = Context(services: services, theme: theme)
        installed = context
        let parked = waiters
        waiters = [:]
        for continuation in parked.values {
            continuation.resume(returning: context)
        }
    }

    /// Replace only the presentation identity while retaining the current
    /// store-sharing service stack.
    public func updateTheme(_ theme: WhereTheme) {
        guard let installed else { return }
        self.installed = Context(services: installed.services, theme: theme)
    }

    /// Release the installed stack, so nothing here keeps the app's store alive
    /// once it has logged out of it (a reset, or leaving demo mode). The next
    /// session's `install(_:)` replaces it.
    ///
    /// Intents that fire meanwhile **park**, exactly as they do before the
    /// first install — the alternative is answering from a store the app has
    /// abandoned, which is worse than waiting for the one it opens next.
    public func clear() {
        installed = nil
    }

    /// The installed stack, suspending until the launch installs one. Throws
    /// only `CancellationError`, when the awaiting intent's task is cancelled
    /// while parked.
    ///
    /// Only the parking path is timed: the span's duration is how long an intent
    /// waited on the launch, which is the whole question a Siri-racing-startup
    /// report needs answered. It carries no budget — how long the wait may
    /// reasonably run is the *launch*'s expectation, already declared per step.
    func current() async throws -> WhereServices {
        try await currentContext().services
    }

    /// Resolve services and theme atomically for snippet presentation.
    func currentContext() async throws -> Context {
        if let installed {
            return installed
        }
        return try await WhereIntentsLog.logger.measure(.awaitServices) {
            try await park()
        }
    }

    /// Suspend until `install(_:)` resumes us, keyed so a cancelled waiter can
    /// remove exactly itself.
    private func park() async throws -> Context {
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
