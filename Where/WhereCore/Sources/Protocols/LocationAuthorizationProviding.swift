public protocol LocationAuthorizationProviding: Sendable {
    func currentAuthorizationStatus() async -> TrackingAuthorizationStatus
    func requestAlwaysAuthorization() async
}
