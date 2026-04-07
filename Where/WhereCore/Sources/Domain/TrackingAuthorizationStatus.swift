public enum TrackingAuthorizationStatus: String, Codable, Sendable {
    case notDetermined
    case authorizedWhenInUse
    case authorizedAlways
    case denied
    case restricted

    public var isBackgroundAuthorized: Bool {
        self == .authorizedAlways
    }
}
