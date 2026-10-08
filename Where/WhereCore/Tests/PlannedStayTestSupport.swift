import Foundation
import RegionKit
@testable import WhereCore

/// Shared exact-date fixtures for planning persistence and backup tests.
enum PlannedStayTestSupport {
    static func stay(
        id: PlannedStay.ID = .init(rawValue: UUID()),
        region: Region = .newYork,
        arrival: CalendarDay = .init(year: 2026, month: 10, day: 10),
        departure: CalendarDay = .init(year: 2026, month: 10, day: 24),
    ) throws -> PlannedStay {
        try PlannedStay(
            id: id,
            region: region,
            arrival: .init(earliest: arrival, latest: arrival),
            departure: .init(earliest: departure, latest: departure),
        )
    }

    static func record(
        stay: PlannedStay,
        revisionID: UUID = UUID(),
        updatedAt: Date = .init(timeIntervalSince1970: 1_700_000_000),
    ) throws -> PlannedStayRecord {
        try PlannedStayRecord(id: revisionID, stayID: stay.id, value: stay, updatedAt: updatedAt)
    }
}
