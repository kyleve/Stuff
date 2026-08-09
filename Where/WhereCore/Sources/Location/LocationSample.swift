import Foundation
import RegionKit

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
    /// Read from the location metadata of a photo the user approved importing.
    case photo
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
            case .photo: "photo"
            case .manual: "manual"
            case .evidenceImplied: "evidenceImplied"
        }
    }

    /// Whether this sample came from GPS (passive Visits / significant-change,
    /// or a one-shot foreground fix) rather than user-asserted manual or
    /// evidence-derived data. Exhaustive so a new case forces a decision here.
    public var isGPS: Bool {
        switch self {
            case .gpsVisit, .gpsSignificantChange: true
            case .photo, .manual, .evidenceImplied: false
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
        for candidate in knownCases where candidate.discriminator == discriminator {
            // Exhaustive over `SampleSource` (no `default`): adding a
            // new case forces a compile error here, surfacing the
            // discriminator <-> case mapping that needs updating.
            switch candidate {
                case .gpsVisit: return .gpsVisit
                case .gpsSignificantChange: return .gpsSignificantChange
                case .photo: return .photo
                case .manual: return .manual
                case .evidenceImplied:
                    guard let evidenceId,
                          let evidenceKindRaw,
                          let kind = EvidenceKind.fromDiscriminator(evidenceKindRaw)
                    else { return nil }
                    return .evidenceImplied(id: evidenceId, kind: kind)
            }
        }
        return nil
    }

    /// Used by `fromDiscriminator` to walk every case exhaustively.
    /// `.evidenceImplied` uses placeholder associated values; they're
    /// only here to make the case visitable for discriminator
    /// matching.
    private static let knownCases: [SampleSource] = [
        .gpsVisit,
        .gpsSignificantChange,
        .photo,
        .manual,
        .evidenceImplied(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            kind: .other(nil),
        ),
    ]
}

/// A single point-in-time observation of where the user was. The smallest
/// unit of data that flows through `WhereCore`.
public struct LocationSample: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let coordinate: Coordinate
    public let horizontalAccuracy: Double
    public let source: SampleSource
    /// Installation that produced an automatic GPS sample. Nil for legacy
    /// samples and user-asserted/manual data.
    public let recordingDeviceID: RecordingDeviceID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        coordinate: Coordinate,
        horizontalAccuracy: Double,
        source: SampleSource,
        recordingDeviceID: RecordingDeviceID? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
        self.recordingDeviceID = recordingDeviceID
    }

    /// Stamp an automatic sample with the installation that received it.
    /// User-asserted samples intentionally remain device-agnostic.
    func recorded(by deviceID: RecordingDeviceID) -> LocationSample {
        guard source.isGPS else { return self }
        return LocationSample(
            id: id,
            timestamp: timestamp,
            coordinate: coordinate,
            horizontalAccuracy: horizontalAccuracy,
            source: source,
            recordingDeviceID: deviceID,
        )
    }
}
