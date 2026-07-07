import Foundation
import RegionKit

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
        for candidate in knownCases where candidate.discriminator == discriminator {
            // Exhaustive over `EvidenceKind` (no `default`): adding a
            // new case forces a compile error here, surfacing the
            // discriminator <-> kind mapping that needs updating.
            switch candidate {
                case .planeTicket: return .planeTicket
                case .boardingPass: return .boardingPass
                case .hotelReceipt: return .hotelReceipt
                case .carRental: return .carRental
                case .rideshare: return .rideshare
                case .photo: return .photo
                case .document: return .document
                case .other: return .other(otherLabel)
            }
        }
        return nil
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
}

/// Coarse classification of the bytes attached to an `Evidence` record.
/// Readers use this to pick the right preview/loader (PDF viewer vs.
/// image view vs. plain-text rendering vs. raw download). The bytes
/// themselves live in `EvidenceBlobStore`; this enum is purely a
/// rendering hint.
///
/// `.other` carries an optional label (typically a MIME-ish hint like
/// `"application/zip"`) so unclassified blobs are still attributable
/// without forcing every new media format to grow a first-class case.
public enum EvidenceContentType: Sendable, Hashable, Codable {
    case pdf
    /// Any UIImage-decodable format (jpeg/png/heic/etc.). UI decides
    /// which loader to use based on byte sniffing.
    case image
    case plainText
    case rawData
    case other(String?)

    /// Stable identifier used for SwiftData persistence and for
    /// matching against discriminator strings on the wire. The
    /// `.other` label is excluded; round-tripping callers persist it
    /// in a sibling column (see `SDEvidence.contentTypeOtherLabel`).
    public var discriminator: String {
        switch self {
            case .pdf: "pdf"
            case .image: "image"
            case .plainText: "plainText"
            case .rawData: "rawData"
            case .other: "other"
        }
    }

    /// Reconstruct from a discriminator plus an optional `.other` label.
    /// Returns `nil` for unknown discriminators so callers can choose
    /// whether to log, drop, or substitute a default.
    public static func fromDiscriminator(
        _ discriminator: String,
        otherLabel: String? = nil,
    ) -> EvidenceContentType? {
        for candidate in knownCases where candidate.discriminator == discriminator {
            switch candidate {
                case .pdf: return .pdf
                case .image: return .image
                case .plainText: return .plainText
                case .rawData: return .rawData
                case .other: return .other(otherLabel)
            }
        }
        return nil
    }

    /// Mirrors `EvidenceKind.knownCases`: enumerates each family once,
    /// using `.other(nil)` as the placeholder for the labeled case.
    public static let knownCases: [EvidenceContentType] = [
        .pdf,
        .image,
        .plainText,
        .rawData,
        .other(nil),
    ]
}

/// A user-attached record that supports a claim about where they were on a
/// given date.
///
/// `Evidence` is metadata only: the optional bytes are stored separately by
/// `EvidenceBlobStore`. `contentType` is a rendering hint telling the UI
/// how to interpret those bytes when they're fetched (PDF preview vs.
/// image view vs. plain-text vs. raw download); use `.other(nil)` for
/// unclassified attachments.
public struct Evidence: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let kind: EvidenceKind
    public let capturedAt: Date
    public let region: Region?
    public let note: String?
    public let contentType: EvidenceContentType

    public init(
        id: UUID = UUID(),
        kind: EvidenceKind,
        capturedAt: Date,
        region: Region? = nil,
        note: String? = nil,
        contentType: EvidenceContentType,
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.region = region
        self.note = note
        self.contentType = contentType
    }
}
