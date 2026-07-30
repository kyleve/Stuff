import Foundation
import Observation

/// Persists which application runtime should be constructed on the next
/// process launch.
///
/// The control value lives in its own defaults suite, separate from the
/// application domain Inspector exposes for editing. Clearing app preferences
/// therefore cannot strand or unexpectedly exit the developer tool.
@MainActor
@Observable
public final class InspectorModeController {
    public enum NextLaunch: Equatable, Sendable {
        case regularApplication
        case inspector
    }

    public private(set) var nextLaunch: NextLaunch

    private let userDefaults: UserDefaults
    private static let enabledKey = "inspector.nextLaunch.enabled"

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        nextLaunch = userDefaults.bool(forKey: Self.enabledKey)
            ? .inspector
            : .regularApplication
    }

    /// Build the dedicated persistent controller for one application.
    public convenience init(applicationIdentifier: String) {
        let suiteName = "\(applicationIdentifier).inspector-control"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to open Inspector defaults suite \(suiteName)")
        }
        self.init(userDefaults: userDefaults)
    }

    public func enterInspectorOnNextLaunch() {
        userDefaults.set(true, forKey: Self.enabledKey)
        nextLaunch = .inspector
    }

    public func useRegularApplicationOnNextLaunch() {
        userDefaults.removeObject(forKey: Self.enabledKey)
        nextLaunch = .regularApplication
    }
}
