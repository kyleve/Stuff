public enum TrackingStatus: String, Codable, Sendable {
    case healthy
    case needsReview
    case needsAttention

    public var title: String {
        switch self {
            case .healthy:
                "Tracking is healthy"
            case .needsReview:
                "Review recent activity"
            case .needsAttention:
                "Open the app"
        }
    }
}
