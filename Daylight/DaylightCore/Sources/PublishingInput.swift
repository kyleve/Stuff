import Foundation

public struct PublishingInput: Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case capturedImage, sequenceHighlight }
    public let kind: Kind
    public let image: CapturedImage
    public let event: SolarEvent
    public let timeZoneIdentifier: String
    public let renderedURL: URL
    public init(
        kind: Kind,
        image: CapturedImage,
        event: SolarEvent,
        timeZoneIdentifier: String,
        renderedURL: URL,
    ) {
        self.kind = kind; self.image = image; self.event = event
        self.timeZoneIdentifier = timeZoneIdentifier; self.renderedURL = renderedURL
    }
}
