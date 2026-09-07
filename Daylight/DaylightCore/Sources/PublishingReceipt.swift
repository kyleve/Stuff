import Foundation

public struct PublishingReceipt: Codable, Equatable, Sendable {
    public let remoteID: String
    public let url: URL
    public init(remoteID: String, url: URL) {
        self.remoteID = remoteID; self.url = url
    }
}
