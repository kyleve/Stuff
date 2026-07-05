import Foundation
import Observation

/// Takes and releases the OS-level assertion behind ``SleepInhibitor``.
/// Production uses the `ProcessInfo`-backed implementation; tests conform a
/// recorder so no real assertion is taken.
@MainActor
@_spi(Testing)
public protocol SleepAssertionBackend: AnyObject {
    func begin(reason: String)
    func end()
}

/// The real assertion: `ProcessInfo.beginActivity(.idleSystemSleepDisabled)`.
@MainActor
final class ProcessInfoSleepAssertionBackend: SleepAssertionBackend {
    private var token: NSObjectProtocol?

    func begin(reason: String) {
        token = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: reason,
        )
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}

/// Holds a `ProcessInfo` activity assertion that blocks *idle* system sleep
/// (the `caffeinate -i` equivalent) while workers run. Display sleep and an
/// explicit lid close are unaffected.
///
/// `setActive` is idempotent per direction: reasserting the current state is a
/// no-op, so callers can recompute freely after every state change and the
/// underlying activity is begun/ended exactly once per transition.
@MainActor
@Observable
public final class SleepInhibitor {
    /// Whether an assertion is currently held. Observable so the UI can show
    /// a "preventing sleep" indicator.
    public private(set) var isActive = false

    @ObservationIgnored private let backend: any SleepAssertionBackend

    public init() {
        backend = ProcessInfoSleepAssertionBackend()
    }

    /// Swaps the real assertion for a test double.
    @_spi(Testing)
    public init(backend: any SleepAssertionBackend) {
        self.backend = backend
    }

    public func setActive(_ active: Bool, reason: String) {
        guard active != isActive else { return }
        isActive = active
        if active {
            backend.begin(reason: reason)
        } else {
            backend.end()
        }
    }
}
