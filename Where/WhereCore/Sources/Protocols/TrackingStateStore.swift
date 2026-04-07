public protocol TrackingStateStore: Sendable {
    func load() async -> TrackingState
    func save(_ state: TrackingState) async
}
