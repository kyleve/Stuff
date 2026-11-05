import Foundation

/// Major-one GPS travels in the same atomic envelope as other versioned history. A foundation
/// reader can observe its required major even when the shared requirement arrives later.
enum VersionedLocationSample {
    static let kind = "recording.observation"
    private static let version = DataSemanticsVersion(major: 1, minor: 0, patch: 0)
    /// Physical storage understands the foundation and recording envelopes. The caller's scoped
    /// permit can admit a smaller set and always checks headers before reaching this adapter.
    static let storagePolicy = DataCompatibilityPolicy(current: version, supportedMajors: [0, 1])

    static func encode(
        _ sample: LocationSample,
        generationID: WhereDataGenerationID,
    ) throws -> VersionedHistoryRecord {
        guard sample.source.isGPS else { throw DataCompatibilityError.incompleteRecord }
        try sample.validateRecordingContract()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try VersionedHistoryRecord(
            id: .init(rawValue: sample.id),
            dataGenerationID: generationID,
            semantics: version,
            scope: .entireHistory,
            kind: kind,
            payload: encoder.encode(sample),
        )
    }

    static func decode(_ record: VersionedHistoryRecord) throws -> LocationSample {
        guard record.semantics.major == version.major else {
            throw DataCompatibilityError.updateRequired(requiredMajor: record.semantics.major)
        }
        guard record.kind == kind, record.scope == .entireHistory else {
            throw DataCompatibilityError.incompleteRecord
        }
        let sample = try JSONDecoder().decode(LocationSample.self, from: record.payload)
        guard sample.source.isGPS, sample.id == record.id.rawValue else {
            throw DataCompatibilityError.conflictingRecord
        }
        try sample.validateRecordingContract()
        return sample
    }
}
