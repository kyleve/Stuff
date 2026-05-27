import Foundation

/// Where each `LocationSample` came from. Recorded so reports can distinguish
/// passive GPS data from user-asserted history.
///
/// `.evidenceImplied` carries the originating `Evidence.id` plus its kind so
/// reports can render a quick attribution ("from a boarding pass on
/// 2025-08-12") without re-fetching every evidence row.
public enum SampleSource: Sendable, Hashable, Codable {
    /// A `CLVisit` arrival callback.
    case gpsVisit
    /// A `CLLocationManager` significant-change callback.
    case gpsSignificantChange
    /// User typed in a coordinate or picked a place after the fact.
    case manual
    /// Derived from an attached piece of evidence (e.g. a boarding pass).
    /// `kind` is a denormalized copy of `Evidence.kind` for fast filtering;
    /// the canonical evidence (with notes, label, blob, etc.) is fetched by
    /// `id` from `WhereStore`.
    case evidenceImplied(id: UUID, kind: EvidenceKind)

    /// Stable identifier shared across persistence and Codable. Mirrors the
    /// pattern on `EvidenceKind.discriminator`.
    public var discriminator: String {
        switch self {
            case .gpsVisit: "gpsVisit"
            case .gpsSignificantChange: "gpsSignificantChange"
            case .manual: "manual"
            case .evidenceImplied: "evidenceImplied"
        }
    }

    /// `.evidenceImplied` only — the originating evidence's UUID. Returns
    /// `nil` for the other cases, so SwiftData can skip writing the column.
    public var evidenceId: UUID? {
        if case let .evidenceImplied(id, _) = self { id } else { nil }
    }

    /// `.evidenceImplied` only — the originating evidence's kind.
    public var evidenceKind: EvidenceKind? {
        if case let .evidenceImplied(_, kind) = self { kind } else { nil }
    }

    /// Reconstruct from a discriminator plus optional evidence fields.
    /// Returns `nil` for unknown discriminators; returns `nil` for
    /// `.evidenceImplied` when `evidenceId`/`evidenceKindRaw` are missing
    /// (the sample is half-stored and the caller should drop it).
    public static func fromDiscriminator(
        _ discriminator: String,
        evidenceId: UUID? = nil,
        evidenceKindRaw: String? = nil,
    ) -> SampleSource? {
        switch discriminator {
            case "gpsVisit": .gpsVisit
            case "gpsSignificantChange": .gpsSignificantChange
            case "manual": .manual
            case "evidenceImplied":
                if let evidenceId,
                   let evidenceKindRaw,
                   let kind = EvidenceKind.fromDiscriminator(evidenceKindRaw)
                {
                    .evidenceImplied(id: evidenceId, kind: kind)
                } else {
                    nil
                }
            default: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case evidenceId
        case evidenceKindRaw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let discriminator = try container.decode(String.self, forKey: .source)
        let evidenceId = try container.decodeIfPresent(UUID.self, forKey: .evidenceId)
        let evidenceKindRaw = try container.decodeIfPresent(String.self, forKey: .evidenceKindRaw)
        guard let value = SampleSource.fromDiscriminator(
            discriminator,
            evidenceId: evidenceId,
            evidenceKindRaw: evidenceKindRaw,
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .source,
                in: container,
                debugDescription: "Unknown or incomplete SampleSource '\(discriminator)'",
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(discriminator, forKey: .source)
        if case let .evidenceImplied(id, kind) = self {
            try container.encode(id, forKey: .evidenceId)
            try container.encode(kind.discriminator, forKey: .evidenceKindRaw)
        }
    }
}

/// A single point-in-time observation of where the user was. The smallest
/// unit of data that flows through `WhereCore`.
public struct LocationSample: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let coordinate: Coordinate
    public let horizontalAccuracy: Double
    public let source: SampleSource

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        coordinate: Coordinate,
        horizontalAccuracy: Double,
        source: SampleSource,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }
}
