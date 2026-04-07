public protocol TrackingNotificationScheduling: Sendable {
    func schedule(_ request: TrackingNotificationRequest) async
    func cancel(ids: [String]) async
}
