import Foundation

/// Waits only for launch progress, never for user interaction. Cancellation
/// stops this waiter without cancelling the shared recording launch.
@MainActor
enum AutomaticBackupLaunchReadiness {
    enum State {
        case pending
        case ready
        case unavailable
    }

    static func wait(readState: () -> State) async throws -> Bool {
        while true {
            try Task.checkCancellation()
            switch readState() {
                case .ready: return true
                case .unavailable: return false
                case .pending: try await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
