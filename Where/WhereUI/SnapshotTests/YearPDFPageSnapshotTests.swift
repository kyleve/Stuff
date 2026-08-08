import PDFKit
import RegionKit
import SnapshotKitTesting
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct YearPDFPageSnapshotTests {
    @Test func representativePages() async throws {
        let file = try await YearPDFRenderer().render(document: Self.document) { _ in }
        defer { try? FileManager.default.removeItem(at: file.storageDirectory) }
        let pdf = try #require(PDFDocument(url: file.url))

        for (name, index) in [
            ("cover", 0),
            ("daily", 3),
            ("manual", 4),
            ("evidence", 5),
            ("raw-gps", 7),
        ] {
            let page = try #require(pdf.page(at: index))
            let image = page.thumbnail(of: page.bounds(for: .mediaBox).size, for: .mediaBox)
            assertSnapshot(
                of: image,
                as: .image(precision: 0.99, perceptualPrecision: 0.99),
                named: name,
            )
        }
    }

    private static var document: YearPDFDocument {
        let timestamp = date("2024-06-01T12:00:00-07:00")
        let attributed = (0 ..< 30).map { index in
            YearAuditAttributedSample(
                sample: LocationSample(
                    id: UUID(uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        index + 1,
                    ))!,
                    timestamp: timestamp.addingTimeInterval(TimeInterval(index)),
                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                    horizontalAccuracy: 8,
                    source: index.isMultiple(of: 2) ? .gpsVisit : .gpsSignificantChange,
                ),
                region: .california,
            )
        }
        let manual = DayPresence(
            day: CalendarDay(year: 2024, month: 6, day: 2),
            regions: [.newYork],
            audit: ManualEntryAudit(
                recordedAt: date("2024-07-01T09:00:00-07:00"),
                note: "Verified against travel documents.",
                location: nil,
            ),
        )
        let report = YearAuditReport(
            report: YearReport(
                year: 2024,
                days: [
                    DayPresence(
                        day: CalendarDay(year: 2024, month: 6, day: 1),
                        regions: [.california],
                    ),
                    DayPresence(
                        day: CalendarDay(year: 2024, month: 6, day: 2),
                        regions: [.newYork],
                    ),
                ],
                totals: [.california: 1, .newYork: 1],
            ),
            samples: attributed,
            manualDays: [manual],
            evidence: [
                Evidence(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    kind: .boardingPass,
                    capturedAt: timestamp,
                    region: .california,
                    note: "Flight confirmation",
                    contentType: .pdf,
                ),
            ],
            trackedRegions: [.california, .newYork, .canada, .europeanUnion],
            timeZone: timeZone,
            regionDataSources: RegionDataSource.all,
        )
        return YearPDFDocument(
            audit: report,
            generatedAt: date("2026-07-31T15:04:05.123-07:00"),
            reportID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            preparedFor: "Alex Example",
            reference: "Tax file 2024",
            pageSize: .letter,
            includeRawGPS: true,
            isDemo: false,
            buildInfo: .current(bundle: .main),
        )
    }

    private static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    private static func date(_ value: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)!
    }
}
