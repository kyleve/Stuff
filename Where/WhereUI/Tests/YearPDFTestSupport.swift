import Foundation
import RegionKit
@_spi(Testing) import WhereCore
@testable import WhereUI

enum YearPDFTestSupport {
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static let buildInfo = BuildInfo(infoDictionary: [
        "CFBundleShortVersionString": "3.4",
        "CFBundleVersion": "567",
    ])

    static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)!
    }

    static func audit(
        year: Int = 2024,
        gpsCount: Int = 2,
        note: String = "Reviewed against itinerary.",
    ) -> YearAuditReport {
        let base = date("2024-02-29T12:00:00-08:00")
        let samples = (0 ..< gpsCount).map { index -> YearAuditAttributedSample in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
            let sample = LocationSample(
                id: id,
                timestamp: base.addingTimeInterval(TimeInterval(index)),
                coordinate: Coordinate(
                    latitude: 37.7749 + Double(index) / 100_000,
                    longitude: -122.4194,
                ),
                horizontalAccuracy: 7.4,
                source: index.isMultiple(of: 2) ? .gpsVisit : .gpsSignificantChange,
            )
            return YearAuditAttributedSample(sample: sample, region: .california)
        }
        let manual = DayPresence(
            day: CalendarDay(year: year, month: 3, day: 1),
            regions: [.california, .newYork],
            isAuthoritative: false,
            audit: ManualEntryAudit(
                recordedAt: date("2024-04-01T10:30:00-07:00"),
                note: note,
                location: CapturedLocation(
                    coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                    horizontalAccuracy: 11,
                    timestamp: date("2024-04-01T10:29:58-07:00"),
                ),
            ),
        )
        let days = [
            DayPresence(day: CalendarDay(year: year, month: 2, day: 29), regions: [.california]),
            DayPresence(
                day: CalendarDay(year: year, month: 3, day: 1),
                regions: [.california, .newYork],
            ),
        ]
        return YearAuditReport(
            report: YearReport(
                year: year,
                days: days,
                totals: [.california: 2, .newYork: 1],
            ),
            samples: samples,
            manualDays: [manual],
            evidence: [
                Evidence(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    kind: .boardingPass,
                    capturedAt: date("2024-02-29T11:00:00-08:00"),
                    region: .california,
                    note: "SFO to JFK - 予約番号 É123",
                    contentType: .pdf,
                ),
            ],
            trackedRegions: [.california, .newYork, .canada, .europeanUnion],
            timeZone: timeZone,
            regionDataSources: RegionDataSource.all,
        )
    }

    static func document(
        pageSize: YearPDFPageSize = .letter,
        includeRawGPS: Bool = false,
        isDemo: Bool = false,
        gpsCount: Int = 2,
        note: String = "Reviewed against itinerary.",
    ) -> YearPDFDocument {
        YearPDFDocument(
            audit: audit(gpsCount: gpsCount, note: note),
            generatedAt: date("2026-07-31T15:04:05.123-07:00"),
            reportID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            preparedFor: "Alex Example",
            reference: "Tax file 2024",
            pageSize: pageSize,
            includeRawGPS: includeRawGPS,
            isDemo: isDemo,
            buildInfo: buildInfo,
        )
    }
}
