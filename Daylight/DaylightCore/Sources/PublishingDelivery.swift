import Foundation

/// Adapter checkpoint data is opaque to capture orchestration and versioned by the adapter.
public struct PublishingDelivery: Codable, Equatable, Sendable, Identifiable {
    public struct ID: Codable, Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let destination: PublishingDestinationID
    public let imageID: CaptureSequence.Slot.ID
    public let kind: PublishingInput.Kind
    public var checkpoint: Data?
    public var state: State
    public enum State: Codable, Equatable, Sendable {
        case pending, retry(Date, String), delivered(PublishingReceipt), needsAttention(String)
    }

    public init(
        destination: PublishingDestinationID,
        imageID: CaptureSequence.Slot.ID,
        kind: PublishingInput.Kind,
    ) {
        id = .init(rawValue: UUID()); self.destination = destination; self.imageID = imageID
        self.kind = kind; state = .pending
    }
}
