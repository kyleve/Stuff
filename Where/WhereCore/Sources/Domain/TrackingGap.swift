import Foundation

public struct TrackingGap: Equatable, Sendable {
    public let date: Date
    public let reason: String

    public init(date: Date, reason: String) {
        self.date = date
        self.reason = reason
    }
}
