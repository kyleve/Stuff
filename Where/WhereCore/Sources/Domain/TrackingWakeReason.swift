public enum TrackingWakeReason: String, Codable, Sendable {
    case appLaunch
    case significantLocationChange
    case visit
    case regionBoundary
    case backgroundRefresh
    case manualRefresh

    public var title: String {
        switch self {
            case .appLaunch:
                "App Launch"
            case .significantLocationChange:
                "Significant Change"
            case .visit:
                "Visit"
            case .regionBoundary:
                "Region Boundary"
            case .backgroundRefresh:
                "Background Refresh"
            case .manualRefresh:
                "Manual Refresh"
        }
    }
}
