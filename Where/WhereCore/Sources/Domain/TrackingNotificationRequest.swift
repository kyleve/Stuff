import Foundation

public struct TrackingNotificationRequest: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let deliverAt: Date

    public init(
        id: String,
        title: String,
        body: String,
        deliverAt: Date,
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.deliverAt = deliverAt
    }
}
