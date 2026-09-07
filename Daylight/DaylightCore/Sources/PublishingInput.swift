import Foundation

public struct PublishingInput: Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case capturedImage, sequenceHighlight }
    public let kind: Kind
    public let image: CapturedImage
    public let event: SolarEvent
    public let timeZoneIdentifier: String
    public let imageURL: URL
    public let rawURL: URL?
    public init(
        kind: Kind,
        image: CapturedImage,
        event: SolarEvent,
        timeZoneIdentifier: String,
        imageURL: URL,
        rawURL: URL?,
    ) {
        self.kind = kind; self.image = image; self.event = event
        self.timeZoneIdentifier = timeZoneIdentifier; self.imageURL = imageURL; self.rawURL = rawURL
    }
}
