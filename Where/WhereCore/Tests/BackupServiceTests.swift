import Foundation
import RegionKit
import Testing
import WhereCore

struct BackupServiceTests {
    private static let calendar = WhereCoreTestSupport.calendar()

    // Whole-second timestamps so the `.iso8601` date strategy (no
    // fractional seconds) round-trips exactly.
    private static let exportDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let evidenceWithBlobId =
        UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let evidenceNoBlobId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private static func sampleFixtures() -> [LocationSample] {
        [
            LocationSample(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .gpsVisit,
            ),
            LocationSample(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                timestamp: Date(timeIntervalSince1970: 1_700_100_000),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 10,
                source: .evidenceImplied(id: evidenceWithBlobId, kind: .boardingPass),
            ),
            LocationSample(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                timestamp: Date(timeIntervalSince1970: 1_700_200_000),
                coordinate: Coordinate(latitude: 41.8781, longitude: -87.6298),
                horizontalAccuracy: 8,
                source: .photo,
            ),
        ]
    }

    private static func evidenceFixtures() -> [Evidence] {
        [
            Evidence(
                id: evidenceWithBlobId,
                kind: .boardingPass,
                capturedAt: Date(timeIntervalSince1970: 1_700_050_000),
                region: .california,
                note: "SFO → JFK",
                contentType: .pdf,
            ),
            Evidence(
                id: evidenceNoBlobId,
                kind: .other("ferry ticket"),
                capturedAt: Date(timeIntervalSince1970: 1_700_060_000),
                region: nil,
                note: nil,
                contentType: .other(nil),
            ),
        ]
    }

    private static func manualDayFixtures() -> [DayPresence] {
        [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                in: calendar,
                regions: [.california, .newYork],
            ),
        ]
    }

    private static func dismissedIssueFixtures() -> [DismissedIssue] {
        [
            DismissedIssue(
                id: .borderDrift(day: CalendarDay(year: 2026, month: 4, day: 1)),
                dismissedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ),
            DismissedIssue(
                id: .missingDays(start: CalendarDay(year: 2026, month: 1, day: 5)),
                dismissedAt: Date(timeIntervalSince1970: 1_700_100_000),
            ),
        ]
    }

    @Test func archiveFileRoundTripsEveryTableAndBlobs() throws {
        let service = BackupService()
        let samples = Self.sampleFixtures()
        let evidence = Self.evidenceFixtures()
        let manualDays = Self.manualDayFixtures()
        let blobs: [UUID: Data] = [Self.evidenceWithBlobId: Data("boarding-pass-pdf".utf8)]

        let dismissedIssues = Self.dismissedIssueFixtures()

        let url = try service.makeArchiveFile(
            samples: samples,
            evidence: evidence,
            manualDays: manualDays,
            dismissedIssues: dismissedIssues,
            blobs: blobs,
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Email-friendly, date-stamped filename.
        #expect(url.pathExtension == "zip")
        #expect(url.lastPathComponent.hasPrefix("Where Backup "))

        let result = try service.readArchive(at: url)
        #expect(result.archive.formatVersion == BackupArchive.currentFormatVersion)
        #expect(result.archive.exportedAt == Self.exportDate)
        #expect(result.archive.samples == samples)
        #expect(result.archive.evidence == evidence)
        #expect(result.archive.manualDays == manualDays)
        // Dismissals round-trip verbatim, id and timestamp.
        #expect(result.archive.dismissedIssues == dismissedIssues)
        // Only the evidence with bytes gets an asset; the other is metadata-only.
        #expect(result.archive.assets.map(\.evidenceId) == [Self.evidenceWithBlobId])
        #expect(result.blobs == blobs)
    }

    @Test func archiveNameIsDateAndTimeStamped() throws {
        let service = BackupService()
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: [],
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // `Where Backup <yyyy-MM-dd> <HH.mm>.zip`. The time renders in the local
        // time zone, so match the shape rather than a fixed instant.
        let name = url.lastPathComponent
        #expect(
            name.wholeMatch(of: /Where Backup \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.zip/) != nil,
            "Unexpected archive name: \(name)",
        )
    }

    @Test func authoritativeManualDaySurvivesArchiveRoundTrip() throws {
        let service = BackupService()
        let manualDays = [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                in: Self.calendar,
                regions: [.newYork],
                isAuthoritative: true,
            ),
        ]
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: manualDays,
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try service.readArchive(at: url)
        #expect(result.archive.manualDays == manualDays)
        #expect(result.archive.manualDays.first?.isAuthoritative == true)
    }

    @Test func trackedRegionsSurviveArchiveRoundTrip() throws {
        let service = BackupService()
        let texas = try #require(Region(rawValue: "us-TX"))
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: [],
            trackedRegions: [.california, texas],
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try service.readArchive(at: url)
        #expect(result.archive.trackedRegions == [.california, texas])
    }

    @Test func primaryRegionAppearanceSurvivesArchiveRoundTrip() throws {
        let service = BackupService()
        let texas = try #require(Region(rawValue: "us-TX"))
        let primary = [
            PrimaryRegion(
                region: .california,
                appearance: RegionAppearance(
                    color: .orange,
                    emoji: "🌴",
                    symbolName: "sun.max.fill",
                ),
                order: 0,
            ),
            PrimaryRegion(region: texas, appearance: nil, order: 1),
        ]
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: [],
            trackedRegions: primary.map(\.region),
            primaryRegions: primary,
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try service.readArchive(at: url)
        #expect(result.archive.primaryRegions == primary)
        // The bare-id list is written alongside for the summary count.
        #expect(result.archive.trackedRegions == [.california, texas])
    }

    @Test func auditManualDaySurvivesArchiveRoundTrip() throws {
        let service = BackupService()
        let manualDays = [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                in: Self.calendar,
                regions: [.california],
                isAuthoritative: true,
                audit: ManualEntryAudit(
                    recordedAt: Date(timeIntervalSince1970: 1_700_050_000),
                    note: "Reviewed my calendar.",
                    location: CapturedLocation(
                        coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                        horizontalAccuracy: 12,
                        timestamp: Date(timeIntervalSince1970: 1_700_050_000),
                    ),
                ),
            ),
        ]
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: manualDays,
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try service.readArchive(at: url)
        #expect(result.archive.manualDays == manualDays)
        #expect(result.archive.manualDays.first?.audit == manualDays.first?.audit)
    }

    @Test func manifestRoundTripsThroughJSON() throws {
        let archive = BackupArchive(
            exportedAt: Self.exportDate,
            samples: Self.sampleFixtures(),
            evidence: Self.evidenceFixtures(),
            manualDays: Self.manualDayFixtures(),
            dismissedIssues: Self.dismissedIssueFixtures(),
            trackedRegions: [.california, .newYork],
            primaryRegions: [
                PrimaryRegion(
                    region: .california,
                    appearance: RegionAppearance(
                        color: .orange,
                        emoji: "🌴",
                        symbolName: "sun.max.fill",
                    ),
                    order: 0,
                ),
                PrimaryRegion(region: .newYork, appearance: nil, order: 1),
            ],
            assets: [BackupAssetEntry(
                evidenceId: Self.evidenceWithBlobId,
                filename: "assets/\(Self.evidenceWithBlobId.uuidString)",
            )],
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupArchive.self, from: data)

        #expect(decoded == archive)
        #expect(decoded.formatVersion == 3)
    }

    @Test func readingAFileThatIsNotAZipThrows() throws {
        let service = BackupService()
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try Data("definitely not a zip".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        #expect(throws: (any Error).self) {
            _ = try service.readArchive(at: bogus)
        }
    }
}
