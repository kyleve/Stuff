import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct PhotoHistoryCommitTests {
    private let day = CalendarDay(year: 2026, month: 1, day: 1)
    private let instant = Date(timeIntervalSince1970: 1_767_227_400)
    private let primary = [PrimaryRegion(region: .california, appearance: nil, order: 0)]

    private func fixture() throws -> ReviewedPhotoHistory {
        let observation = try #require(PhotoObservation(
            capturedAt: instant,
            addedAt: instant,
            coordinate: .init(
                latitude: 43,
                longitude: -79,
            ),
            accuracy: nil,
        ))
        let point = DatedPhotoLocation(observation: observation, day: day, region: .ontario)
        return ReviewedPhotoHistory(
            points: [.init(original: point, day: day, region: .newYork)],
            assertedDays: [.init(
                day: day.adding(days: 1),
                regions: [.ontario],
            )],
        )
    }

    private func services(store: SwiftDataStore) -> WhereServices {
        WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(timeZone: WhereCoreTestSupport.pacific),
            now: { Date(timeIntervalSinceReferenceDate: 800_000_000.0.nextUp) },
        )
    }

    @Test(arguments: [BackupCoordinator.ImportStrategy.merge, .replace])
    func approvedDaysSurviveTravelNewYearAndPortableBackup(_ strategy: BackupCoordinator
        .ImportStrategy) async throws
    {
        let store = try SwiftDataStore.inMemory()
        let services = services(store: store)
        let receipt = try await services.preparePhotoReceipt(in: .local)
        let history = try fixture()
        for _ in 0 ..< 2 {
            let conflicts = try await services.commitPhotoHistory(
                history,
                primary: primary,
                receipt: receipt,
                resolution: nil,
            )
            #expect(conflicts == nil)
        }
        #expect(try await services.hasCommittedPhotoHistory(receipt))
        let raw = try #require(try await store.allSamples().first)
        #expect(try await store.allSamples().count == 1)
        #expect(raw.timestamp == instant)
        #expect(raw.horizontalAccuracy < 0)
        #expect(!raw.source.isGPS)
        #expect(raw.source.photoAttribution?.observedRegion == .ontario)
        #expect(raw.source.photoAttribution?.region == .newYork)
        #expect(try await services.reports.yearReport(for: 2025).days.isEmpty)
        #expect(try await services.reports.yearReport(for: 2026).totals == [
            .newYork: 1,
            .ontario: 1,
        ])
        #expect(try await services.reports.locations(onDay: day)[.newYork]?.count == 1)
        #expect(try await store.primaryRegions() == primary)
        let url = try await services.backup.exportBackup()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let destination = try SwiftDataStore.inMemory()
        let reopened = self.services(store: destination)
        _ = try await reopened.backup.importAndAcknowledgeBackup(from: url, strategy: strategy)
        #expect(try await destination.allSamples() == [raw])
        #expect(try await destination.allManualDays() == store.allManualDays())
        try await reopened.journal.clearYear(2025)
        #expect(try await reopened.reports.yearReport(for: 2026).totals == [
            .newYork: 1,
            .ontario: 1,
        ])
        try await reopened.journal.clearYear(2026)
        #expect(try await destination.allSamples().isEmpty)
    }

    @Test func revalidatesConflictAndPreservesOriginalAudit() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = services(store: store)
        let earlier = ManualEntryAudit(recordedAt: instant, note: "prior range", location: nil)
        let gap = day.adding(days: 1)
        let row = DayPresence(
            day: gap,
            regions: [.california],
            isAuthoritative: true,
            audit: earlier,
        )
        try await store.perform { try await store.setManualDay(row) }
        let receipt = try await services.preparePhotoReceipt(in: .local)
        let draft = try fixture()
        let evidence = try #require(try await services.commitPhotoHistory(
            draft,
            primary: primary,
            receipt: receipt,
            resolution: nil,
        ))
        #expect(evidence.manualDays == [row])
        #expect(try await store.allSamples().isEmpty)
        let decision = PhotoHistoryResolution(
            evidence: evidence,
            useReviewedDays: [gap],
            useReviewedPicks: false,
        )
        try await store.perform { try await store.clearManualDay(gap) }
        let changed = try #require(try await services.commitPhotoHistory(
            draft,
            primary: primary,
            receipt: receipt,
            resolution: decision,
        ))
        #expect(changed.isEmpty)
        #expect(try await store.allSamples().isEmpty)
        try await store.perform { try await store.setManualDay(row) }
        let completed = try await services.commitPhotoHistory(
            draft,
            primary: primary,
            receipt: receipt,
            resolution: decision,
        )
        #expect(completed == nil)
        let saved = try #require(try await store.allManualDays().first)
        #expect(saved.regions == [.california, .ontario])
        #expect(saved.isAuthoritative)
        #expect(saved.audit == earlier)
        #expect(saved.photoApprovedAt != nil)
    }

    @Test func keepExistingPicksAndAuthoritativeDays() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = services(store: store)
        let picks = [PrimaryRegion(region: .ontario, appearance: nil, order: 0)]
        let original = DayPresence(day: day, regions: [.california], isAuthoritative: true)
        try await store.perform {
            try await store.setManualDay(original)
            try await store.setPrimaryRegions(picks)
        }
        let token = try await services.preparePhotoReceipt(in: .local)
        let history = try fixture()
        let conflict = try #require(try await services.commitPhotoHistory(
            history,
            primary: primary,
            receipt: token,
            resolution: nil,
        ))
        #expect(conflict.primaryRegions == picks)
        let keep = PhotoHistoryResolution(
            evidence: conflict,
            useReviewedDays: [],
            useReviewedPicks: false,
        )
        let finished = try await services.commitPhotoHistory(
            history,
            primary: primary,
            receipt: token,
            resolution: keep,
        )
        #expect(finished == nil)
        #expect(try await store.primaryRegions() == picks)
        #expect(try await store.allSamples().isEmpty)
        #expect(try await services.reports.yearReport(for: 2026).totals == [
            .california: 1,
            .ontario: 1,
        ])
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .backupReplace,
                changedBy: token.installationID,
                at: instant,
            )
        }
        #expect(try await !services.hasCommittedPhotoHistory(token))
        await #expect(throws: RecordingPersistenceError.dataGenerationChanged) {
            try await services.commitPhotoHistory(
                history,
                primary: primary,
                receipt: token,
                resolution: keep,
            )
        }
    }

    @Test func failedTransactionRollsBackPhotosChoicesAndReceiptTogether() async throws {
        struct SaveFailure: Error {}
        let store = try SwiftDataStore.inMemory()
        let services = services(store: store)
        let token = try await services.preparePhotoReceipt(in: .local)
        let draft = try fixture()
        await #expect(throws: SaveFailure.self) {
            try await store.perform {
                _ = try await services.commitPhotoHistory(
                    draft,
                    primary: primary,
                    receipt: token,
                    resolution: nil,
                )
                throw SaveFailure()
            }
        }
        #expect(try await store.allSamples().isEmpty)
        #expect(try await store.allManualDays().isEmpty)
        #expect(try await !store.hasExplicitPrimaryRegions())
        #expect(try await !services.hasCommittedPhotoHistory(token))
        let result = try await services.commitPhotoHistory(
            draft,
            primary: primary,
            receipt: token,
            resolution: nil,
        )
        #expect(result == nil)
        #expect(try await services.hasCommittedPhotoHistory(token))
    }

    @Test func coldStoreRetainsApprovedDaysAfterPrimaryRegionsChange() async throws {
        let fixtureStore = try TemporaryHistoryStore()
        defer { fixtureStore.remove() }
        let receipt: PhotoHistoryReceipt
        do {
            let services = services(store: SwiftDataStore(modelContainer: fixtureStore.container))
            receipt = try await services.preparePhotoReceipt(in: .local)
            let result = try await services.commitPhotoHistory(
                fixture(),
                primary: primary,
                receipt: receipt,
                resolution: nil,
            )
            #expect(result == nil)
            try await services.setPrimaryRegions([.init(
                region: .ontario,
                appearance: nil,
                order: 0,
            )])
            await services.shutdown()
        }
        let reopened =
            try services(store: SwiftDataStore(modelContainer: fixtureStore.makeContainer()))
        #expect(try await reopened.hasCommittedPhotoHistory(receipt))
        #expect(try await reopened.reports.yearReport(for: 2026).totals == [
            .ontario: 1,
            .newYork: 1,
        ])
        let points = try await reopened.reports.locations(onDay: day)
        #expect(points[.newYork]?.first?.isPhoto == true)
        await reopened.shutdown()
    }
}
