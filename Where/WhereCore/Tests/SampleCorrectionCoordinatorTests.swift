import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct SampleCorrectionCoordinatorTests {
    @Test(.disabled(
        if: ProcessInfo.processInfo.environment["WHERE_FLIGHT_VERIFICATION_CONFIG"] == nil,
        "Supply a local flight-verification configuration to replay an external backup.",
    ))
    func productionArchiveCorrectionOnRequest() async throws {
        let path = try #require(ProcessInfo.processInfo
            .environment["WHERE_FLIGHT_VERIFICATION_CONFIG"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let configuration = try decoder.decode(
            FlightArchiveVerificationConfiguration.self,
            from: Data(contentsOf: URL(fileURLWithPath: path)),
        )
        let backupURL = URL(fileURLWithPath: configuration.backupPath)
        let archive = try BackupService().readArchive(at: backupURL).archive
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: configuration.calendarTimeZoneID))
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: RegionAttributor(for: archive.trackedRegions),
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            now: { configuration.now },
        )
        _ = try await services.backup.importAndAcknowledgeBackup(
            from: backupURL,
            strategy: .replace,
        )
        let day = CalendarDay(from: configuration.from, in: calendar)
        let review = try await services.corrections.review(
            id: .flightDay(day: day),
            year: day.year,
            primaryRegions: archive.trackedRegions,
            driftThresholdMeters: 1000,
        )
        let proposal = try #require(review?.proposal)
        #expect(proposal.resultingRegions == configuration.expectedResultingRegions)
        guard case .applied = try await services.corrections.apply(proposal) else {
            Issue.record("The archive's unchanged reviewed correction must apply")
            return
        }
        let result = try await services.reports.yearReport(for: day.year)
        #expect(result.days.first { $0.day == day }?.regions == configuration
            .expectedResultingRegions)
        #expect(try await Set(store.allSamples()) == Set(archive.samples))
    }

    @Test func changedTrackedRegionsRejectApplyBeforeLiveObserverReconciles() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: nil, order: 0),
            ])
            for sample in FlightTrajectoryFixtures.turningFlight().samples {
                try await store.add(sample: sample)
            }
        }
        // Hold the live cache at the reviewed policy. Store-backed snapshots
        // must see a committed policy change before the stream observer does.
        let live = RegionAttribution(
            store: store,
            changes: AsyncStream { $0.finish() },
            initial: RegionAttributor(for: [.california]),
            trackedIDs: [Region.california.rawValue],
        )
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: live,
            aggregator: SampleCorrectionTestSupport.aggregator,
            now: { FlightTrajectoryFixtures.date(minutes: 150) },
        )
        let day = CalendarDay(
            from: FlightTrajectoryFixtures.start,
            in: SampleCorrectionTestSupport.calendar,
        )
        let review = try await services.corrections.review(
            id: .flightDay(day: day),
            year: day.year,
            primaryRegions: [.california],
            driftThresholdMeters: 1000,
        )
        let proposal = try #require(review?.proposal)
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .newYork, appearance: nil, order: 0),
            ])
        }
        #expect(live.loadedRegions == [.california])
        let result = try await services.corrections.apply(proposal)
        guard case let .stale(fresh) = result else {
            Issue.record("A committed attribution policy change must require fresh review")
            return
        }
        let replacement = try #require(fresh?.proposal)
        // The invented route lies outside both real policies, so this test
        // detects the policy change even though its effective presence is equal.
        #expect(replacement.resultingRegions == proposal.resultingRegions)
        #expect(replacement.evidence.trackedRegions == [.newYork])
        #expect(proposal.evidence.trackedRegions == [.california])
        #expect(try await store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func applyOnlyRevisesReviewedSamplesAndPreservesRawTrajectory() async throws {
        let h = try await SampleCorrectionTestSupport.completedFlight()
        let proposal = try await h.proposal()
        let originals = try await h.store.allSamples()
        let result = try await h.coordinator.apply(proposal)
        guard case .applied = result else {
            Issue.record("An unchanged completed flight review must apply")
            return
        }

        let revisions = try await h.store.allSampleAttributionRevisions()
        #expect(Set(revisions.map(\.sampleID)) == Set(proposal.edits.map(\.sampleID)))
        #expect(revisions.count == proposal.edits.count)
        #expect(try await Set(h.store.allSamples()) == Set(originals))
        #expect(try await h.reader.manualDays(inYear: h.day.year).isEmpty)
        #expect(try await h.reader.yearReport(for: h.day.year).days.first?.regions == proposal
            .resultingRegions)

        let fresh = try await h.coordinator.review(
            id: proposal.reviewID,
            year: h.day.year,
            primaryRegions: SampleCorrectionTestSupport.attribution.loadedRegions,
            driftThresholdMeters: 1000,
        )
        #expect(fresh?.proposal == nil)
        #expect(fresh?.flight != nil)
        #expect(try await h.reader.dataIssueReads(for: h.day.year).history.rawSamples
            .count == originals.count)

        let second = try await h.coordinator.apply(proposal)
        guard case .stale = second else {
            Issue.record("A committed proposal must not be applied twice")
            return
        }
        #expect(try await h.store.allSampleAttributionRevisions().count == revisions.count)
    }

    enum InterveningChange: CaseIterable {
        case sample
        case manual
        case revision
        case generation
    }

    @Test(arguments: InterveningChange.allCases)
    func changedEvidenceRejectsApplyWithoutWritingAnyCorrections(
        change: InterveningChange,
    ) async throws {
        let h = try await SampleCorrectionTestSupport.completedFlight()
        let proposal = try await h.proposal()
        try await h.store.perform {
            switch change {
                case .sample:
                    try await h.store.add(sample: FlightTrajectoryFixtures.sample(
                        401,
                        minutes: 146,
                        east: 1445,
                        north: 8,
                    ))
                case .manual:
                    try await h.store.setManualDay(.init(
                        day: h.day,
                        regions: [.canada],
                        isAuthoritative: true,
                        audit: nil,
                    ))
                case .revision:
                    try await h.store.addSampleAttributionRevision(.init(
                        id: UUID(),
                        sampleID: FlightTrajectoryFixtures.sampleID(1),
                        updatedAt: FlightTrajectoryFixtures.date(minutes: 149),
                        replacementRegions: [.california],
                    ))
                case .generation:
                    _ = try await h.store.rotateDataGeneration(
                        reason: .accountReset,
                        changedBy: FlightTrajectoryFixtures.device,
                        at: FlightTrajectoryFixtures.date(minutes: 149),
                    )
            }
        }
        let before = try await h.store.allSampleAttributionRevisions()
        let result = try await h.coordinator.apply(proposal)
        guard case .stale = result else {
            Issue.record("Changed review evidence must require another review: \(change)")
            return
        }
        #expect(try await h.store.allSampleAttributionRevisions() == before)
    }
}
