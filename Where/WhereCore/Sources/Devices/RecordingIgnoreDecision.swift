import Foundation

/// An immutable change to one device's automatic eligibility. Resume and undo both restore
/// eligibility, but carry different reviewed periods. Neither changes explicit source choices.
public struct RecordingIgnoreDecision: Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        /// Persist the domain identity as a bare UUID.
        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(UUID.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var value = encoder.singleValueContainer()
            try value.encode(rawValue)
        }

        public static func < (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            lhs.rawValue.uuidString < rhs.rawValue.uuidString
        }
    }

    public enum Action: Hashable, Sendable { case ignored, eligible }
    public enum Change: Hashable, Codable, Sendable {
        case ignore(Until)
        case restoreEligibility
    }

    /// The inclusive calendar date selected by the user, its original zone, and its fixed end.
    /// Decode preserves the saved instant; travel or time-zone database changes cannot move it.
    public struct Until: Hashable, Codable, Sendable {
        public let day: CalendarDay
        public let timeZone: TimeZone
        public let end: Date
        /// Offset immediately before the fixed end, retained for wire validation without new zone
        /// rules.
        public let endSecondsFromGMT: Int

        public init(day: CalendarDay, timeZone: TimeZone) throws {
            guard (1 ... 9999).contains(day.year),
                  CalendarDay(iso: day.iso8601) == day else { throw ValidationError.invalidEnd }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let instant = calendar.date(from: DateComponents(
                year: day.year,
                month: day.month,
                day: day.day,
            )),
                CalendarDay(from: instant, in: calendar) == day,
                let bounds = calendar.dateInterval(of: .day, for: instant)
            else {
                throw ValidationError.invalidEnd
            }
            self.day = day
            self.timeZone = timeZone
            end = bounds.end
            endSecondsFromGMT = timeZone.secondsFromGMT(for: bounds.end.addingTimeInterval(-1))
            try validate()
        }

        public func validate() throws {
            guard (1 ... 9999).contains(day.year), CalendarDay(iso: day.iso8601) == day,
                  end.timeIntervalSinceReferenceDate.isFinite,
                  let savedZone = TimeZone(secondsFromGMT: endSecondsFromGMT)
            else {
                throw ValidationError.invalidEnd
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = savedZone
            let lastSecond = end.addingTimeInterval(-1)
            guard calendar.component(.era, from: lastSecond) == 1,
                  CalendarDay(from: lastSecond, in: calendar) == day,
                  calendar.dateInterval(of: .day, for: lastSecond)?.end == end
            else {
                throw ValidationError.invalidEnd
            }
        }
    }

    public enum ValidationError: Error { case invalidEnd, invalidScope }
    public let id: ID
    public let author: RecordingDeviceID
    public let deviceID: RecordingDeviceID
    public let periods: [RecordingPeriod]
    public let change: Change
    let predecessorIDs: [ID]
    public var predecessors: Set<ID> {
        Set(predecessorIDs)
    }

    public let version: DataSemanticsVersion

    public init(
        id: ID,
        author: RecordingDeviceID,
        deviceID: RecordingDeviceID,
        periods: [RecordingPeriod],
        change: Change,
        predecessors: Set<ID>,
        version: DataSemanticsVersion,
    ) throws {
        for period in periods {
            try period.validate()
        }
        let periods = RecordingPeriod.union(periods)
        self.id = id
        self.author = author
        self.deviceID = deviceID
        self.periods = periods
        self.change = change
        predecessorIDs = predecessors.sorted()
        self.version = version
        try validate()
    }

    /// A shortened ignore claims its original tail as eligible in this same immutable record.
    /// No separately delivered restoration is needed to make the new end date take effect.
    public func action(at instant: Date) -> Action {
        switch change {
            case let .ignore(until): instant < until.end ? .ignored : .eligible
            case .restoreEligibility: .eligible
        }
    }

    public func validate() throws {
        guard !periods.isEmpty else { throw ValidationError.invalidScope }
        for period in periods {
            try period.validate()
        }
        switch change {
            case let .ignore(until):
                try until.validate()
                guard periods.count == 1,
                      periods[0].start < until.end,
                      periods[0].end >= until.end else { throw ValidationError.invalidScope }
            case .restoreEligibility: break
        }
    }
}

extension RecordingIgnoreDecision: CausalPeriodOperation {
    var actionChangeInstants: [Date] {
        switch change {
            case let .ignore(until): [until.end]
            case .restoreEligibility: []
        }
    }
}
