import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct BackupServiceTests {
    private static let calendar = WhereCoreTestSupport.calendar()

    private static let exportDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let evidenceWithBlobId =
        UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let evidenceNoBlobId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private static let recordingDeviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
    )

    private static func sampleFixtures() -> [LocationSample] {
        [
            LocationSample(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .gpsVisit,
                recordingDeviceID: recordingDeviceID,
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

    private static let recordingMetadataID = RecordingDeviceMetadataChange.ID(
        rawValue: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
    )

    private static func recordingDeviceProfileFixtures() -> [RecordingDeviceProfile] {
        [
            RecordingDeviceProfile(
                id: recordingDeviceID,
                systemName: "iPad",
                kind: .tablet,
                registeredAt: exportDate,
                registrationGenerationID: .initial,
            ),
        ]
    }

    private static func recordingDeviceMetadataFixtures() -> [RecordingDeviceMetadataChange] {
        [
            RecordingDeviceMetadataChange(
                id: recordingMetadataID,
                deviceID: recordingDeviceID,
                revision: 0,
                changedAt: exportDate,
                changedByDeviceID: recordingDeviceID,
                payload: .nickname("Travel iPad"),
            ),
        ]
    }

    private static func recordingDeviceCheckInFixtures() -> [RecordingDeviceCheckIn] {
        [
            RecordingDeviceCheckIn(
                deviceID: recordingDeviceID,
                revision: 0,
                lastSeenAt: exportDate,
                status: .recording,
            ),
        ]
    }

    private static func archive() -> BackupArchive {
        BackupArchive(
            exportedAt: exportDate,
            samples: [],
            evidence: [],
            manualDays: [],
            dismissedIssues: [],
            trackedRegions: [],
            primaryRegions: [],
            recordingDeviceProfiles: recordingDeviceProfileFixtures(),
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
            assets: [],
        )
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
        let recordingDeviceProfiles = Self.recordingDeviceProfileFixtures()
        let recordingDeviceMetadataChanges = Self.recordingDeviceMetadataFixtures()
        let deviceArchive = RecordingDeviceRemoval(
            id: .init(rawValue: UUID()),
            deviceID: Self.recordingDeviceID,
            removedAt: Self.exportDate,
            removedByDeviceID: Self.recordingDeviceID,
        )

        let url = try service.makeArchiveFile(
            samples: samples,
            evidence: evidence,
            manualDays: manualDays,
            dismissedIssues: dismissedIssues,
            recordingDeviceProfiles: recordingDeviceProfiles,
            recordingDeviceMetadataChanges: recordingDeviceMetadataChanges,
            recordingDeviceRemovals: [deviceArchive],
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
        #expect(result.archive.recordingDeviceProfiles == recordingDeviceProfiles)
        #expect(result.archive.recordingDeviceMetadataChanges == recordingDeviceMetadataChanges)
        #expect(result.archive.recordingDeviceRemovals == [deviceArchive])
        let encodedManifest = try #require(String(
            data: BackupService.makeEncoder().encode(result.archive),
            encoding: .utf8,
        ))
        #expect(encodedManifest.contains("\"isEnabled\"") == false)
        #expect(encodedManifest.contains("\"registrationGenerationID\""))
        #expect(encodedManifest.contains("00000000-0000-0000-0000-0000000000E0"))
        // Only the evidence with bytes gets an asset; the other is metadata-only.
        #expect(result.archive.assets.map(\.evidenceId) == [Self.evidenceWithBlobId])
        #expect(result.blobs == blobs)
    }

    @Test func olderFormatIsRejectedBeforeItsMissingCurrentFieldsAreDecoded() {
        let legacyManifest = Data(#"{"formatVersion":4}"#.utf8)

        do {
            _ = try BackupService.decodeManifest(legacyManifest)
            Issue.record("Expected the legacy backup format to be rejected.")
        } catch BackupService.BackupError.unsupportedFormatVersion(4) {
            // Expected: the version envelope was decoded before the strict v6 shape.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func currentFormatDoesNotSilentlyBackfillAMissingProfileGeneration() throws {
        let data = try BackupService.makeEncoder().encode(
            Self.archive(),
        )
        var manifest = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let profiles = try #require(
            manifest["recordingDeviceProfiles"] as? [[String: Any]],
        )
        manifest["recordingDeviceProfiles"] = profiles.map { profile in
            var profile = profile
            profile.removeValue(forKey: "registrationGenerationID")
            return profile
        }

        do {
            _ = try BackupService.decodeManifest(
                JSONSerialization.data(withJSONObject: manifest),
            )
            Issue.record("Expected the missing registration generation to be rejected.")
        } catch let DecodingError.keyNotFound(key, _) {
            #expect(key.stringValue == "registrationGenerationID")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func decoderRejectsANegativeMetadataRevisionFromABackup() throws {
        let archive = BackupArchive(
            exportedAt: Self.exportDate,
            samples: [],
            evidence: [],
            manualDays: [],
            dismissedIssues: [],
            trackedRegions: [],
            primaryRegions: [],
            recordingDeviceProfiles: Self.recordingDeviceProfileFixtures(),
            recordingDeviceMetadataChanges: Self.recordingDeviceMetadataFixtures(),
            recordingDeviceRemovals: [],
            assets: [],
        )
        var json = try #require(String(
            data: BackupService.makeEncoder().encode(archive),
            encoding: .utf8,
        ))
        let revision = try #require(json.range(of: "\"revision\" : 0"))
        json.replaceSubrange(revision, with: "\"revision\" : -1")
        do {
            _ = try BackupService.makeDecoder().decode(
                BackupArchive.self,
                from: Data(json.utf8),
            )
            Issue.record("Expected the negative metadata revision to be rejected.")
        } catch DecodingError.dataCorrupted {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func archiveNameIsDateAndTimeStamped() throws {
        let service = BackupService()
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: [],
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
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
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
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
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
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
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
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
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
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
            recordingDeviceProfiles: Self.recordingDeviceProfileFixtures(),
            recordingDeviceMetadataChanges: Self.recordingDeviceMetadataFixtures(),
            recordingDeviceRemovals: [],
            assets: [BackupAssetEntry(
                evidenceId: Self.evidenceWithBlobId,
                filename: "assets/\(Self.evidenceWithBlobId.uuidString)",
            )],
        )

        let data = try BackupService.makeEncoder().encode(archive)
        let decoded = try BackupService.makeDecoder().decode(BackupArchive.self, from: data)

        #expect(decoded == archive)
        #expect(decoded.formatVersion == BackupArchive.currentFormatVersion)
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

    @Test func loadingADeclaredAssetThrowsWhenItsFileIsMissing() throws {
        let extractDirectory = FileManager.default.temporaryDirectory.appending(
            path: "where-missing-backup-asset-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(
            at: extractDirectory,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: extractDirectory) }
        let entry = BackupAssetEntry(
            evidenceId: Self.evidenceWithBlobId,
            filename: "assets/\(Self.evidenceWithBlobId.uuidString)",
        )

        do {
            _ = try BackupService.loadAssets([entry], from: extractDirectory)
            Issue.record("Expected a missing manifest-declared asset to throw.")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoSuchFile)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
