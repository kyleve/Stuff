import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct BackupServiceTests {
    private struct UpgradeVerificationConfiguration: Decodable {
        let backupPath: String
        let samplesCount: Int
        let evidenceCount: Int
        let manualDaysCount: Int
        let dismissedIssuesCount: Int
        let trackedRegionsCount: Int
        let primaryRegionsCount: Int
        let deviceProfilesCount: Int
        let deviceChangesCount: Int
        let deviceRemovalsCount: Int
        let plannedStayRecordsCount: Int
        let homeRegionRecordsCount: Int
        let sampleAttributionRevisionsCount: Int
        let assetsCount: Int
    }

    private static let calendar = WhereCoreTestSupport.calendar()

    private static let exportDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let evidenceWithBlobId =
        UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let evidenceNoBlobId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private static let recordingDeviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
    )

    @Test(
        .disabled(
            if: ProcessInfo.processInfo.environment["WHERE_BACKUP_VERIFICATION_CONFIG"] == nil,
            "Run through the upgrade-where-backup skill.",
        ),
    )
    func upgradedBackupDecodesAndLoadsAssets() throws {
        let configurationPath = try #require(
            ProcessInfo.processInfo.environment["WHERE_BACKUP_VERIFICATION_CONFIG"],
        )
        let configuration = try JSONDecoder().decode(
            UpgradeVerificationConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: configurationPath)),
        )
        let result = try BackupService().readArchive(
            at: URL(fileURLWithPath: configuration.backupPath),
        )

        #expect(result.archive.formatVersion == BackupArchive.currentFormatVersion)
        #expect(result.archive.samples.count == configuration.samplesCount)
        #expect(result.archive.evidence.count == configuration.evidenceCount)
        #expect(result.archive.manualDays.count == configuration.manualDaysCount)
        #expect(result.archive.dismissedIssues.count == configuration.dismissedIssuesCount)
        #expect(result.archive.trackedRegions.count == configuration.trackedRegionsCount)
        #expect(result.archive.primaryRegions.count == configuration.primaryRegionsCount)
        #expect(result.archive.recordingDeviceProfiles.count == configuration.deviceProfilesCount)
        #expect(result.archive.recordingDeviceMetadataChanges.count == configuration
            .deviceChangesCount)
        #expect(result.archive.recordingDeviceRemovals.count == configuration.deviceRemovalsCount)
        #expect(result.archive.plannedStayRecords.count == configuration.plannedStayRecordsCount)
        #expect(result.archive.homeRegionRecords.count == configuration.homeRegionRecordsCount)
        #expect(result.archive.sampleAttributionRevisions.count == configuration
            .sampleAttributionRevisionsCount)
        #expect(result.archive.assets.count == configuration.assetsCount)
        #expect(result.blobs.count == configuration.assetsCount)
    }

    private static func sampleFixtures() -> [LocationSample] {
        [
            LocationSample(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 5,
                source: .gpsVisit,
                recordingDeviceID: recordingDeviceID,
                motion: LocationMotion(
                    speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 2),
                    altitude: .init(meters: 11000, accuracyMeters: 12),
                ),
            ),
            LocationSample(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                timestamp: Date(timeIntervalSince1970: 1_700_100_000),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 10,
                source: .evidenceImplied(id: evidenceWithBlobId, kind: .boardingPass),
                assertedByDeviceID: WhereCoreTestSupport.authorID,
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
            .hardwareModelIdentifier("iPad13,18", for: recordingDeviceProfileFixtures()[0]),
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

    private static func plannedStayFixtures() throws -> [PlannedStayRecord] {
        let stayID = try PlannedStay.ID(rawValue: #require(UUID(
            uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
        )))
        return try [PlannedStayTestSupport.record(
            stay: PlannedStayTestSupport.stay(id: stayID),
            revisionID: #require(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")),
            updatedAt: exportDate,
        )]
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
            recordingDeviceMetadataChanges: recordingDeviceMetadataFixtures(),
            recordingDeviceRemovals: [],
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
            assets: [],
        )
    }

    private static func attributionFixtures() -> [SampleAttributionRevision] {
        let sampleID = sampleFixtures()[0].id
        let replacements: [Set<Region>?] = [[], [.newYork], nil]
        return replacements.enumerated().map { offset, regions in
            SampleAttributionRevision(
                id: .init(rawValue: UUID()),
                sampleID: sampleID,
                updatedAt: exportDate.addingTimeInterval(Double(offset)),
                changedByDeviceID: recordingDeviceID,
                replacementRegions: regions,
            )
        }
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
                addedByDeviceID: WhereCoreTestSupport.authorID,
            ),
            Evidence(
                id: evidenceNoBlobId,
                kind: .other("ferry ticket"),
                capturedAt: Date(timeIntervalSince1970: 1_700_060_000),
                region: nil,
                note: nil,
                contentType: .other(nil),
                addedByDeviceID: WhereCoreTestSupport.authorID,
            ),
        ]
    }

    private static func manualDayFixtures() -> [DayPresence] {
        [
            DayPresence(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                in: calendar,
                regions: [.california, .newYork],
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
        ]
    }

    private static func dismissedIssueFixtures() -> [DismissedIssue] {
        [
            DismissedIssue(
                id: .borderDrift(day: CalendarDay(year: 2026, month: 4, day: 1)),
                dismissedAt: Date(timeIntervalSince1970: 1_700_000_000),
                dismissedByDeviceID: WhereCoreTestSupport.authorID,
            ),
            DismissedIssue(
                id: .missingDays(start: CalendarDay(year: 2026, month: 1, day: 5)),
                dismissedAt: Date(timeIntervalSince1970: 1_700_100_000),
                dismissedByDeviceID: WhereCoreTestSupport.authorID,
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
        let sampleAttributionRevisions = Self.attributionFixtures()
        let homeRegionRecords = try [
            HomeRegionRecord(
                id: UUID(),
                region: .california,
                updatedAt: Self.exportDate,
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
            HomeRegionRecord(
                id: UUID(),
                region: nil,
                updatedAt: Self.exportDate.addingTimeInterval(1),
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
        ]
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
            plannedStayRecords: Self.plannedStayFixtures(),
            homeRegionRecords: homeRegionRecords,
            sampleAttributionRevisions: sampleAttributionRevisions,
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
        #expect(try result.archive.plannedStayRecords == Self.plannedStayFixtures())
        #expect(result.archive.sampleAttributionRevisions == sampleAttributionRevisions)
        #expect(result.archive.homeRegionRecords == homeRegionRecords)
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

    @Test(arguments: [5, 6, 7, 8, 9, 10, BackupArchive.currentFormatVersion + 1])
    func unsupportedFormatIsRejectedBeforeItsMissingCurrentFieldsAreDecoded(version: Int) {
        let legacyManifest = Data("{\"formatVersion\":\(version)}".utf8)

        do {
            _ = try BackupService.decodeManifest(legacyManifest)
            Issue.record("Expected the unsupported backup format to be rejected.")
        } catch let BackupService.BackupError.unsupportedFormatVersion(rejectedVersion) {
            #expect(rejectedVersion == version)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [false, true])
    func manifestRejectsMissingOrConflictingGPSOrigin(conflicting: Bool) throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        let gps = try #require(
            JSONSerialization
                .jsonObject(with: encoder.encode(Self.sampleFixtures()[0])) as? [String: Any],
        )
        var other = gps
        if conflicting {
            other["recordingDeviceID"] = RecordingDeviceID(rawValue: UUID()).storeURL.absoluteString
            manifest["samples"] = [gps, other]
        } else {
            other.removeValue(forKey: "recordingDeviceID")
            manifest["samples"] = [other]
        }
        #expect(throws: BackupService.BackupError.invalidRecordingData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func currentManifestRejectsMissingActionAuthors() throws {
        let encoder = BackupService.makeEncoder()
        let base = try #require(JSONSerialization
            .jsonObject(with: encoder.encode(Self.archive())) as? [String: Any])
        let rows = try [
            ("manualDays", "changedByDeviceID", encoder.encode(Self.manualDayFixtures()[0])),
            ("evidence", "addedByDeviceID", encoder.encode(Self.evidenceFixtures()[0])),
            (
                "dismissedIssues",
                "dismissedByDeviceID",
                encoder.encode(Self.dismissedIssueFixtures()[0])
            ),
            (
                "primaryRegions",
                "changedByDeviceID",
                encoder.encode(PrimaryRegion(region: .ontario, appearance: nil, order: 0))
            ),
            ("samples", "assertedByDeviceID", encoder.encode(Self.sampleFixtures()[1])),
            (
                "plannedStayRecords",
                "changedByDeviceID",
                encoder.encode(Self.plannedStayFixtures()[0])
            ),
        ]
        for (table, field, data) in rows {
            var manifest = base
            var row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            row.removeValue(forKey: field)
            manifest[table] = [row]
            let bytes = try JSONSerialization.data(withJSONObject: manifest)
            #expect(throws: (any Error).self, "Missing \(table).\(field)") {
                try BackupService.decodeManifest(bytes)
            }
        }
    }

    @Test func conflictingLinkedEvidenceAuthorFailsBeforeRestore() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(JSONSerialization
            .jsonObject(with: encoder.encode(Self.archive())) as? [String: Any])
        var point = try #require(JSONSerialization
            .jsonObject(with: encoder.encode(Self.sampleFixtures()[1])) as? [String: Any])
        point["assertedByDeviceID"] = Self.recordingDeviceID.storeURL.absoluteString
        manifest["samples"] = [point]
        manifest["evidence"] = try JSONSerialization
            .jsonObject(with: encoder.encode(Self.evidenceFixtures()))
        let bytes = try JSONSerialization.data(withJSONObject: manifest)
        #expect(throws: BackupService.BackupError.invalidActionAttribution) {
            try BackupService.decodeManifest(bytes)
        }
    }

    @Test func currentManifestRequiresCorrectionAuthorsBeforeRestore() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        var reset = try #require(
            JSONSerialization
                .jsonObject(with: encoder
                    .encode(Self.attributionFixtures().last)) as? [String: Any],
        )
        reset.removeValue(forKey: "changedByDeviceID")
        manifest["sampleAttributionRevisions"] = [reset]
        do {
            _ = try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
            Issue.record("The backup accepted a reset without an editing device.")
        } catch let DecodingError.keyNotFound(key, _) {
            #expect(key.stringValue == "changedByDeviceID")
        }
    }

    @Test func currentManifestRejectsConflictingCorrectionAuthors() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        let reset = try #require(
            JSONSerialization
                .jsonObject(with: encoder
                    .encode(Self.attributionFixtures().last)) as? [String: Any],
        )
        var conflicting = reset
        conflicting["changedByDeviceID"] = RecordingDeviceID(rawValue: UUID()).storeURL
            .absoluteString
        manifest["sampleAttributionRevisions"] = [reset, conflicting]
        #expect(throws: BackupService.BackupError.invalidRecordingData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func currentManifestRequiresTheModelOfEachArchivedProfile() throws {
        var manifest = try #require(
            JSONSerialization
                .jsonObject(with: BackupService.makeEncoder()
                    .encode(Self.archive())) as? [String: Any],
        )
        manifest["recordingDeviceMetadataChanges"] = []
        #expect(throws: BackupService.BackupError.missingDeviceModel) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func modelFactMustMatchRegistrationAndEveryReplay() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(JSONSerialization
            .jsonObject(with: encoder.encode(Self.archive())) as? [String: Any])
        let profile = Self.recordingDeviceProfileFixtures()[0]
        let fact = RecordingDeviceMetadataChange.hardwareModelIdentifier("iPhone16,1", for: profile)
        var encoded = try #require(JSONSerialization
            .jsonObject(with: encoder.encode(fact)) as? [String: Any])
        encoded["changedAt"] = profile.registeredAt.timeIntervalSince1970 + 1
        manifest["recordingDeviceMetadataChanges"] = [encoded]
        #expect(throws: BackupService.BackupError.invalidRecordingData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
        let conflicting = RecordingDeviceMetadataChange.hardwareModelIdentifier(
            "iPad13,18",
            for: profile,
        )
        manifest["recordingDeviceMetadataChanges"] = try JSONSerialization
            .jsonObject(with: encoder.encode([
                fact,
                conflicting,
            ]))
        #expect(throws: BackupService.BackupError.invalidRecordingData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
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
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
        ]
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: manualDays,
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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
                    symbolName: .sunMaxFill,
                ),
                order: 0,
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
            PrimaryRegion(
                region: texas,
                appearance: nil,
                order: 1,
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
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
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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
                changedByDeviceID: WhereCoreTestSupport.authorID,
            ),
        ]
        let url = try service.makeArchiveFile(
            samples: [],
            evidence: [],
            manualDays: manualDays,
            recordingDeviceProfiles: [],
            recordingDeviceMetadataChanges: [],
            recordingDeviceRemovals: [],
            plannedStayRecords: [],
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
            blobs: [:],
            exportedAt: Self.exportDate,
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = try service.readArchive(at: url)
        #expect(result.archive.manualDays == manualDays)
        #expect(result.archive.manualDays.first?.audit == manualDays.first?.audit)
    }

    @Test func manifestRoundTripsThroughJSON() throws {
        let archive = try BackupArchive(
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
                        symbolName: .sunMaxFill,
                    ),
                    order: 0,
                    changedByDeviceID: WhereCoreTestSupport.authorID,
                ),
                PrimaryRegion(
                    region: .newYork,
                    appearance: nil,
                    order: 1,
                    changedByDeviceID: WhereCoreTestSupport.authorID,
                ),
            ],
            recordingDeviceProfiles: Self.recordingDeviceProfileFixtures(),
            recordingDeviceMetadataChanges: Self.recordingDeviceMetadataFixtures(),
            recordingDeviceRemovals: [],
            plannedStayRecords: Self.plannedStayFixtures(),
            homeRegionRecords: [],
            sampleAttributionRevisions: [],
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

    @Test func currentManifestRejectsInvalidPlanningBeforeImport() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        let records = try Self.plannedStayFixtures()
        var encodedRecords = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(records)) as? [[String: Any]],
        )
        var value = try #require(encodedRecords[0]["value"] as? [String: Any])
        value["arrival"] = [
            "earliest": ["year": 2026, "month": 11, "day": 1],
            "latest": ["year": 2026, "month": 11, "day": 3],
        ]
        encodedRecords[0]["value"] = value
        manifest["plannedStayRecords"] = encodedRecords

        #expect(throws: BackupService.BackupError.invalidPlanningData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func currentManifestRejectsMismatchedStayIdentity() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        var records = try #require(
            JSONSerialization
                .jsonObject(with: encoder.encode(Self.plannedStayFixtures())) as? [[String: Any]],
        )
        records[0]["stayID"] = UUID().uuidString
        manifest["plannedStayRecords"] = records

        #expect(throws: BackupService.BackupError.invalidPlanningData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func currentManifestRejectsUnknownHomeRegion() throws {
        var manifest = try #require(
            JSONSerialization.jsonObject(
                with: BackupService.makeEncoder().encode(Self.archive()),
            ) as? [String: Any],
        )
        manifest["homeRegionRecords"] = [[
            "id": UUID().uuidString,
            "region": "not-a-region",
            "changedByDeviceID": Self.recordingDeviceID.storeURL.absoluteString,
            "updatedAt": 1_700_000_000,
        ]]

        #expect(throws: BackupService.BackupError.invalidPlanningData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
        }
    }

    @Test func currentManifestRejectsUnknownStayDestination() throws {
        let encoder = BackupService.makeEncoder()
        var manifest = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(Self.archive())) as? [String: Any],
        )
        var records = try #require(
            JSONSerialization
                .jsonObject(with: encoder.encode(Self.plannedStayFixtures())) as? [[String: Any]],
        )
        var value = try #require(records[0]["value"] as? [String: Any])
        value["region"] = "not-a-region"
        records[0]["value"] = value
        manifest["plannedStayRecords"] = records

        #expect(throws: BackupService.BackupError.invalidPlanningData) {
            try BackupService.decodeManifest(JSONSerialization.data(withJSONObject: manifest))
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
