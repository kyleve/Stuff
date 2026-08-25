import Foundation

extension FeedHealth {
    var accessibilityDescription: String {
        switch self {
            case .idle: String(localized: .statusDisconnected)
            case .loading: String(localized: .statusLoading)
            case .healthy: String(localized: .statusHealthy)
            case .retrying: String(localized: .statusRetrying)
            case .failed: String(localized: .statusFailed)
            case .quiet: String(localized: .statusQuiet)
        }
    }
}
