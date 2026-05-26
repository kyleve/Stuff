import Foundation

/// What kind of evidence is attached (a boarding pass, hotel receipt, etc.).
/// Used to render an appropriate icon in the UI and to bucket evidence in
/// an audit export.
public enum EvidenceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case planeTicket
    case boardingPass
    case hotelReceipt
    case carRental
    case rideshare
    case photo
    case document
    case other
}

/// A user-attached record that supports a claim about where they were on a
/// given date. Metadata only; the (optional) blob bytes are stored
/// separately via `EvidenceBlobStore` / SwiftData external storage.
public struct Evidence: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let kind: EvidenceKind
    public let capturedAt: Date
    public let region: Region?
    public let note: String?

    public init(
        id: UUID = UUID(),
        kind: EvidenceKind,
        capturedAt: Date,
        region: Region? = nil,
        note: String? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.region = region
        self.note = note
    }
}
