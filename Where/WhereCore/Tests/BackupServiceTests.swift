import Foundation
import RegionKit
import Testing
import WhereCore

struct BackupServiceTests {
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
                regions: [.california, .newYork],
            ),
        ]
    }

    private static func dismissedIssueFixtures() -> [DismissedIssue] {
        [
            DismissedIssue(
                key: "borderDrift:1700000000",
                dismissedAt: Date(timeIntervalSince1970: 1_700_000_000),
            ),
            DismissedIssue(
                key: "missingDays:1700100000",
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
        // Dismissals round-trip verbatim, key and timestamp.
        #expect(result.archive.dismissedIssues == dismissedIssues)
        // Only the evidence with bytes gets an asset; the other is metadata-only.
        #expect(result.archive.assets.map(\.evidenceId) == [Self.evidenceWithBlobId])
        #expect(result.blobs == blobs)
    }

    @Test func authoritativeManualDaySurvivesArchiveRoundTrip() throws {
        let service = BackupService()
        let manualDays = [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
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

    @Test func legacyManualDayWithoutAuthoritativeKeyDecodesAsAdditive() throws {
        // Simulates a manifest written before `isAuthoritative` existed: the
        // missing key must decode as additive rather than failing.
        let json = #"{"date":"2026-07-04T00:00:00Z","regions":["us-NY"]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DayPresence.self, from: Data(json.utf8))
        #expect(decoded.isAuthoritative == false)
        #expect(decoded.regions == [.newYork])
        // A manifest predating audit must decode with no audit, not fail.
        #expect(decoded.audit == nil)
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

    @Test func legacyManifestWithoutTrackedRegionsDecodesAsEmpty() throws {
        // A manifest written before `trackedRegions` existed must decode to []
        // rather than failing (additive field, like `dismissedIssues`).
        let json = #"""
        {"formatVersion":1,"exportedAt":"2026-06-05T12:00:00Z","samples":[],"evidence":[],"manualDays":[],"assets":[]}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BackupArchive.self, from: Data(json.utf8))
        #expect(archive.trackedRegions.isEmpty)
        #expect(archive.dismissedIssues.isEmpty)
    }

    @Test func auditManualDaySurvivesArchiveRoundTrip() throws {
        let service = BackupService()
        let manualDays = [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
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
    }

    @Test func legacyManifestWithoutDismissedIssuesDecodesAsEmpty() throws {
        // Simulates a manifest written before `dismissedIssues` existed: the
        // missing key must decode as empty rather than failing the import.
        let json = """
        {"formatVersion":1,"exportedAt":"2023-11-14T22:13:20Z",\
        "samples":[],"evidence":[],"manualDays":[],"assets":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupArchive.self, from: Data(json.utf8))
        #expect(decoded.dismissedIssues.isEmpty)
        #expect(decoded.formatVersion == 1)
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
