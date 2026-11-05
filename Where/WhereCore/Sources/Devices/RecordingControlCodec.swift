import Foundation

/// Admits the version and stable scope before interpreting a control. Supported older contracts
/// with unknown meaning retain their original bytes and require review instead of becoming
/// automatic.
public enum RecordingControlCodec {
    public enum Admission: Hashable, Sendable {
        case understood(RecordingControl)
        case requiresReview(VersionedHistoryRecord)
    }

    private enum Kind: String {
        case source = "recording.source"
        case ignore = "recording.ignore"
        case place = "recording.place"
        case calendar = "recording.calendar"
    }

    public static func encode(
        _ control: RecordingControl,
        generationID: WhereDataGenerationID,
    ) throws -> VersionedHistoryRecord {
        guard control.version.major == RecordingEvidencePolicy.version.major else {
            throw DataCompatibilityError.updateRequired(requiredMajor: control.version.major)
        }
        try control.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Predecessor arrays and periods have canonical order; sortedKeys also stabilizes enum
        // payload objects. A retry after process restoration produces the same immutable bytes.
        let kind: Kind
        let payload: Data
        switch control {
            case let .source(value):
                kind = .source
                payload = try encoder.encode(value)
            case let .ignore(value):
                kind = .ignore
                payload = try encoder.encode(value)
            case let .place(value):
                kind = .place
                payload = try encoder.encode(value)
            case let .calendar(value):
                kind = .calendar
                payload = try encoder.encode(value)
        }
        return VersionedHistoryRecord(
            id: control.recordID,
            dataGenerationID: generationID,
            semantics: control.version,
            scope: .periods(control.periods),
            kind: kind.rawValue,
            payload: payload,
        )
    }

    public static func admit(
        _ record: VersionedHistoryRecord,
        policy: DataCompatibilityPolicy,
    ) throws -> Admission {
        try policy.validate(requiredMajor: record.semantics.major)
        try record.scope.validate()
        guard record.semantics.major == RecordingEvidencePolicy.version.major,
              let kind = Kind(rawValue: record.kind) else { return .requiresReview(record) }
        let control: RecordingControl = switch kind {
            case .source: try .source(record.decode(HistoryDecision.self, policy: policy))
            case .ignore: try .ignore(record.decode(RecordingIgnoreDecision.self, policy: policy))
            case .place: try .place(record.decode(RecordingPlaceDecision.self, policy: policy))
            case .calendar: try .calendar(record.decode(
                    RecordingCalendarDecision.self,
                    policy: policy,
                ))
        }
        guard control.recordID == record.id, control.version == record.semantics,
              record.scope == .periods(control.periods)
        else { throw DataCompatibilityError.conflictingRecord }
        try control.validate()
        return .understood(control)
    }
}
