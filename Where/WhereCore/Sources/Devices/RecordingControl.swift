import Foundation

/// The four immutable control families in the first multi-device semantics contract.
/// Envelope identities come from the operation itself; encoding never allocates another identity.
public enum RecordingControl: Hashable, Sendable {
    case source(HistoryDecision)
    case ignore(RecordingIgnoreDecision)
    case place(RecordingPlaceDecision)
    case calendar(RecordingCalendarDecision)

    enum Family { case source, ignore, place, calendar }
    var family: Family {
        switch self {
            case .source: .source
            case .ignore: .ignore
            case .place: .place
            case .calendar: .calendar
        }
    }

    var predecessorRecordIDs: Set<VersionedHistoryRecord.ID> {
        switch self {
            case let .source(value): Set(value.predecessors.map { .init(rawValue: $0.rawValue) })
            case let .ignore(value): Set(value.predecessors.map { .init(rawValue: $0.rawValue) })
            case let .place(value): Set(value.predecessors.map { .init(rawValue: $0.rawValue) })
            case let .calendar(value): Set(value.predecessors.map { .init(rawValue: $0.rawValue) })
        }
    }

    public var recordID: VersionedHistoryRecord.ID {
        switch self {
            case let .source(value): .init(rawValue: value.id.rawValue)
            case let .ignore(value): .init(rawValue: value.id.rawValue)
            case let .place(value): .init(rawValue: value.id.rawValue)
            case let .calendar(value): .init(rawValue: value.id.rawValue)
        }
    }

    public var version: DataSemanticsVersion {
        switch self {
            case let .source(value): value.version
            case let .ignore(value): value.version
            case let .place(value): value.version
            case let .calendar(value): value.version
        }
    }

    public var periods: [RecordingPeriod] {
        switch self {
            case let .source(value): value.periods
            case let .ignore(value): value.periods
            case let .place(value): value.periods
            case let .calendar(value): value.periods
        }
    }

    public func validate() throws {
        guard let query = periods.first else { throw DataCompatibilityError.incompleteRecord }
        guard periods == RecordingPeriod.union(periods)
        else { throw DataCompatibilityError.incompleteRecord }
        // Each domain resolver validates all records before resolving the query, including bounds,
        // scope, predecessors, and any immediately visible cycle. Missing predecessors remain
        // valid.
        switch self {
            case let .source(value):
                _ = try HistoryDecisionResolver.resolve([value], within: query, version: version)
            case let .ignore(value):
                _ = try RecordingIgnoreResolver.resolve(
                    [value],
                    for: value.deviceID,
                    within: query,
                    version: version,
                )
            case let .place(value):
                _ = try RecordingPlaceResolver.resolve(
                    [value],
                    for: value.placeID,
                    within: query,
                    version: version,
                )
            case let .calendar(value):
                _ = try RecordingCalendarResolver.resolve(
                    [value],
                    for: value.deviceID,
                    within: query,
                    version: version,
                )
        }
    }
}
