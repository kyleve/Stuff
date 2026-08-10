import Foundation

public protocol ToolClock: Sendable {
    func sleep(for duration: Duration) async throws
    func now() async -> TimeInterval
}

public struct ContinuousToolClock: ToolClock {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }

    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
