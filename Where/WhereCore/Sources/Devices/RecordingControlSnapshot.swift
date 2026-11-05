/// One admitted set of durable controls. Opaque records retain a stable affected scope for
/// review. They never disappear from selection merely because this resolver cannot decode them.
public struct RecordingControlSnapshot: Hashable, Sendable {
    public let generationID: WhereDataGenerationID
    public let records: [VersionedHistoryRecord]
    public let sourceChoices: [HistoryDecision]
    public let ignores: [RecordingIgnoreDecision]
    public let places: [RecordingPlaceDecision]
    public let calendarContexts: [RecordingCalendarDecision]
    public let requiresReview: [VersionedHistoryRecord]

    public init(
        records: [VersionedHistoryRecord],
        generationID: WhereDataGenerationID,
        policy: DataCompatibilityPolicy,
    ) throws {
        var unique: [VersionedHistoryRecord.ID: VersionedHistoryRecord] = [:]
        for record in records {
            guard record.dataGenerationID == generationID
            else { throw RecordingPersistenceError.dataGenerationChanged }
            if let old = unique[record.id],
               old != record { throw DataCompatibilityError.conflictingRecord }
            unique[record.id] = record
        }
        let ordered = unique.values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        var sourceChoices: [HistoryDecision] = []
        var ignores: [RecordingIgnoreDecision] = []
        var places: [RecordingPlaceDecision] = []
        var contexts: [RecordingCalendarDecision] = []
        var requiresReview: [VersionedHistoryRecord] = []
        var understood: [VersionedHistoryRecord.ID: RecordingControl] = [:]
        var observationIDs: Set<VersionedHistoryRecord.ID> = []
        for record in ordered {
            if record.kind == VersionedLocationSample.kind {
                try policy.validate(requiredMajor: record.semantics.major)
                _ = try VersionedLocationSample.decode(record)
                observationIDs.insert(record.id)
                continue
            }
            let admission = try RecordingControlCodec.admit(record, policy: policy)
            if case let .understood(control) = admission { understood[record.id] = control }
            switch admission {
                case let .requiresReview(record): requiresReview.append(record)
                case let .understood(.source(value)): sourceChoices.append(value)
                case let .understood(.ignore(value)): ignores.append(value)
                case let .understood(.place(value)): places.append(value)
                case let .understood(.calendar(value)): contexts.append(value)
            }
        }
        for control in understood.values {
            for predecessorID in control.predecessorRecordIDs {
                guard !observationIDs.contains(predecessorID) else {
                    throw DataCompatibilityError.conflictingRecord
                }
                if let predecessor = understood[predecessorID],
                   predecessor.family != control.family
                {
                    throw DataCompatibilityError.conflictingRecord
                }
            }
        }
        // Validate the complete graphs, including cycles whose individual records are valid and
        // dependencies that arrive for a different device/place. Resolution keeps missing edges.
        if let first = sourceChoices.first, let query = first.periods.first {
            _ = try HistoryDecisionResolver.resolve(
                sourceChoices,
                within: query,
                version: first.version,
            )
        }
        for deviceID in Set(ignores.map(\.deviceID)) {
            if let first = ignores.first(where: { $0.deviceID == deviceID }),
               let query = first.periods.first
            {
                _ = try RecordingIgnoreResolver.resolve(
                    ignores,
                    for: deviceID,
                    within: query,
                    version: first.version,
                )
            }
        }
        for placeID in Set(places.map(\.placeID)) {
            if let first = places.first(where: { $0.placeID == placeID }),
               let query = first.periods.first
            {
                _ = try RecordingPlaceResolver.resolve(
                    places,
                    for: placeID,
                    within: query,
                    version: first.version,
                )
            }
        }
        for deviceID in Set(contexts.map(\.deviceID)) {
            if let first = contexts.first(where: { $0.deviceID == deviceID }),
               let query = first.periods.first
            {
                _ = try RecordingCalendarResolver.resolve(
                    contexts,
                    for: deviceID,
                    within: query,
                    version: first.version,
                )
            }
        }
        self.generationID = generationID
        self.records = ordered.filter { !observationIDs.contains($0.id) }
        self.sourceChoices = sourceChoices
        self.ignores = ignores
        self.places = places
        calendarContexts = contexts
        self.requiresReview = requiresReview
    }
}
