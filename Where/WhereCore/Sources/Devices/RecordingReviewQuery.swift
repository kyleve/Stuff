/// The exact history scope and named devices used by a control preview. Evidence reads include
/// bounded adjacent context; that expansion never broadens the operation's authored periods.
public struct RecordingReviewQuery: Hashable, Sendable {
    public struct PlaceScope: Hashable, Sendable {
        public let placeID: RecordingPlace.ID
        public let intervals: [RecordingInterval]
    }

    public let periods: [RecordingPeriod]
    public let deviceIDs: Set<RecordingDeviceID>
    /// Place-definition reviews need their complete validity, including future changes. They
    /// do not claim a preview of observations or totals beyond a finite history query.
    public let places: [PlaceScope]

    public init(periods: [RecordingPeriod], deviceIDs: Set<RecordingDeviceID>) throws {
        guard !periods.isEmpty else { throw DataCompatibilityError.incompleteRecord }
        for period in periods {
            try period.validate()
        }
        self.periods = RecordingPeriod.union(periods)
        self.deviceIDs = deviceIDs
        places = []
    }

    public init(placeID: RecordingPlace.ID, validity: [RecordingInterval]) throws {
        guard !validity.isEmpty else { throw DataCompatibilityError.incompleteRecord }
        for interval in validity {
            try interval.validate()
        }
        periods = []
        deviceIDs = []
        places = [PlaceScope(placeID: placeID, intervals: RecordingInterval.union(validity))]
    }

    static func combining(_ queries: [Self]) throws -> Self {
        guard !queries.isEmpty else { throw DataCompatibilityError.incompleteRecord }
        let places = Dictionary(grouping: queries.flatMap(\.places), by: \.placeID).map {
            PlaceScope(
                placeID: $0.key,
                intervals: RecordingInterval.union($0.value.flatMap(\.intervals)),
            )
        }.sorted { $0.placeID < $1.placeID }
        return Self(
            periods: RecordingPeriod.union(queries.flatMap(\.periods)),
            deviceIDs: Set(queries.flatMap(\.deviceIDs)),
            places: places,
        )
    }

    var intervals: [RecordingInterval] {
        get throws {
            try RecordingInterval
                .union(periods.map(RecordingInterval.init) + places.flatMap(\.intervals))
        }
    }

    private init(
        periods: [RecordingPeriod],
        deviceIDs: Set<RecordingDeviceID>,
        places: [PlaceScope],
    ) {
        self.periods = periods
        self.deviceIDs = deviceIDs
        self.places = places
    }

    func evidencePeriods() throws -> [RecordingPeriod] {
        let padding = RecordingEvidencePolicy.maximumObservationGap
            + RecordingEvidencePolicy.contextPadding + RecordingEvidencePolicy.pointSupport
        return try RecordingPeriod.union(periods.map {
            try RecordingPeriod(
                start: $0.start.addingTimeInterval(-padding),
                end: $0.end.addingTimeInterval(padding),
            )
        })
    }
}
