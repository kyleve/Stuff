import Foundation
import Observation

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

    private let backend: Backend
    @ObservationIgnored private var token: NSObjectProtocol?

    private enum Backend {
        case processInfo
        /// Test seam: records transitions instead of taking a real assertion.
        case observed(begin: @MainActor () -> Void, end: @MainActor () -> Void)
    }

    public init() {
        backend = .processInfo
    }

    @_spi(Testing)
    public init(
        onBegin: @escaping @MainActor () -> Void,
        onEnd: @escaping @MainActor () -> Void,
    ) {
        backend = .observed(begin: onBegin, end: onEnd)
    }

    public func setActive(_ active: Bool, reason: String) {
        guard active != isActive else { return }
        isActive = active
        switch backend {
            case .processInfo:
                if active {
                    token = ProcessInfo.processInfo.beginActivity(
                        options: .idleSystemSleepDisabled,
                        reason: reason,
                    )
                } else if let token {
                    ProcessInfo.processInfo.endActivity(token)
                    self.token = nil
                }
            case let .observed(begin, end):
                if active {
                    begin()
                } else {
                    end()
                }
        }
    }
}
