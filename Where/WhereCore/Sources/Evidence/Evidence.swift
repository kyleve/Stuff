import Foundation

/// What kind of evidence is attached (a boarding pass, hotel receipt, etc.).
/// Used to render an appropriate icon in the UI and to bucket evidence in
/// an audit export.
///
/// `.other` carries an optional user-supplied label so the catch-all isn't
/// completely opaque ("ferry ticket", "concert receipt"). The label is
/// metadata only — it never affects how the record is stored or compared.
public enum EvidenceKind: Sendable, Hashable, Codable {
    case planeTicket
    case boardingPass
    case hotelReceipt
    case carRental
    case rideshare
    case photo
    case document
    case other(String?)

    /// Stable identifier used for SwiftData / GeoJSON-style persistence and
    /// for matching against discriminator strings on the wire. The `.other`
    /// label is intentionally excluded; round-tripping callers persist that
    /// in a sibling column (see `SDEvidence.otherLabel`).
    public var discriminator: String {
        switch self {
            case .planeTicket: "planeTicket"
            case .boardingPass: "boardingPass"
            case .hotelReceipt: "hotelReceipt"
            case .carRental: "carRental"
            case .rideshare: "rideshare"
            case .photo: "photo"
            case .document: "document"
            case .other: "other"
        }
    }

    /// Reconstruct from a discriminator plus an optional `.other` label.
    /// Returns `nil` for unknown discriminators so callers can choose
    /// whether to log, drop, or substitute a default.
    public static func fromDiscriminator(
        _ discriminator: String,
        otherLabel: String? = nil,
    ) -> EvidenceKind? {
        switch discriminator {
            case "planeTicket": .planeTicket
            case "boardingPass": .boardingPass
            case "hotelReceipt": .hotelReceipt
            case "carRental": .carRental
            case "rideshare": .rideshare
            case "photo": .photo
            case "document": .document
            case "other": .other(otherLabel)
            default: nil
        }
    }

    /// Cases without associated values, plus `.other(nil)`. Replaces the
    /// auto-`CaseIterable` we lost when `.other` gained an associated value.
    public static let knownCases: [EvidenceKind] = [
        .planeTicket,
        .boardingPass,
        .hotelReceipt,
        .carRental,
        .rideshare,
        .photo,
        .document,
        .other(nil),
    ]

    private enum CodingKeys: String, CodingKey {
        case kind
        case otherLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try container.decode(String.self, forKey: .kind)
        let label = try container.decodeIfPresent(String.self, forKey: .otherLabel)
        guard let value = EvidenceKind.fromDiscriminator(discriminator, otherLabel: label) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown EvidenceKind '\(discriminator)'",
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(discriminator, forKey: .kind)
        if case let .other(label) = self {
            try container.encodeIfPresent(label, forKey: .otherLabel)
        }
    }
}

/// Coarse classification of the bytes attached to an `Evidence` record.
/// Readers use this to pick the right preview/loader (PDF viewer vs.
/// image view vs. plain-text rendering vs. raw download). The bytes
/// themselves live in `EvidenceBlobStore`; this enum is purely a
/// rendering hint.
public enum EvidenceContentType: String, Codable, Sendable, Hashable, CaseIterable {
    case pdf
    /// Any UIImage-decodable format (jpeg/png/heic/etc.). UI decides
    /// which loader to use based on byte sniffing.
    case image
    case plainText
    case rawData
}

/// A user-attached record that supports a claim about where they were on a
/// given date.
///
/// `Evidence` is metadata only: the optional bytes are stored separately by
/// `EvidenceBlobStore`. `contentType` is a rendering hint telling the UI
/// how to interpret those bytes when they're fetched (PDF preview vs.
/// image view vs. plain-text vs. raw download).
public struct Evidence: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let kind: EvidenceKind
    public let capturedAt: Date
    public let region: Region?
    public let note: String?
    public let contentType: EvidenceContentType?

    public init(
        id: UUID = UUID(),
        kind: EvidenceKind,
        capturedAt: Date,
        region: Region? = nil,
        note: String? = nil,
        contentType: EvidenceContentType? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.region = region
        self.note = note
        self.contentType = contentType
    }
}
