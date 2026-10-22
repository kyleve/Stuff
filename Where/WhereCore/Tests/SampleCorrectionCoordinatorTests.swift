import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct SampleCorrectionCoordinatorTests {
    @Test(arguments: [30.0, 1440.0])
    func uncertainArrivalRetainsRestorationInUnsupportedGaps(excludedMinute: Double) async throws {
        typealias F = FlightTrajectoryFixtures
        let h = try SampleCorrectionTestSupport.makeHarness(now: F.date(minutes: 4330))
        let excluded = F.sample(4, minutes: excludedMinute, east: 150)
        let peer = F.sample(8, minutes: excludedMinute + 0.1, east: 150)
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 75),
            F.sample(3, minutes: 10, east: 150),
            excluded,
            peer,
            F.sample(5, minutes: 4320, east: 4000),
            F.sample(6, minutes: 4325, east: 4000),
            F.sample(7, minutes: 4330, east: 4000),
        ]
        let originalRevision = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: excluded.id,
            updatedAt: F.date(minutes: 4330),
            replacementRegions: [],
        )
        try await h.store.perform {
            for sample in samples {
                try await h.store.add(sample: sample)
            }
            try await h.store.addSampleAttributionRevision(originalRevision)
        }
        let day = CalendarDay(from: excluded.timestamp, in: SampleCorrectionTestSupport.calendar)
        let reviewID = DataIssueID.flightDay(day: day)
        let review = try #require(await h.coordinator.review(
            id: reviewID,
            year: day.year,
            primaryRegions: SampleCorrectionTestSupport.attribution.loadedRegions,
            driftThresholdMeters: 1000,
        ))
        let flight = try #require(review.flights.first)
        #expect(flight.progress.arrival?.isTimingUncertain == true)
        let restore = try #require(review.pointCorrections.first { $0.sampleID == excluded.id })
        #expect(restore.action == .restoreGPS)
        #expect(!review.pointCorrections.contains { $0.sampleID == peer.id })
        #expect(review.proposal?.edits
            .contains { $0.sampleID == excluded.id || $0.sampleID == peer.id } != true)
        if excludedMinute >= 1440 {
            #expect(!flight.completedDays(in: SampleCorrectionTestSupport.calendar).contains(day))
        }
        guard case .applied = try await h.coordinator.apply(restore) else {
            Issue
                .record(
                    "The reviewed exclusion must remain reversible inside an uncertain arrival gap",
                )
            return
        }
        let revisions = try await h.store.allSampleAttributionRevisions()
        #expect(revisions.contains(originalRevision))
        let reset = try #require(revisions.max { $0.updatedAt < $1.updatedAt })
        #expect(reset.replacementRegions == nil)
        #expect(reset.updatedAt > originalRevision.updatedAt)
        let refreshed = try await h.coordinator.review(
            id: reviewID,
            year: day.year,
            primaryRegions: SampleCorrectionTestSupport.attribution.loadedRegions,
            driftThresholdMeters: 1000,
        )
        #expect(refreshed?.pointCorrections.contains { $0.sampleID == excluded.id } != true)
        if excludedMinute >= 1440 { #expect(refreshed == nil) }
        #expect(try await Set(h.store.allSamples()) == Set(samples))
        guard case .stale = try await h.coordinator.apply(restore) else {
            Issue.record("An already applied restoration must be stale")
            return
        }
        #expect(try await h.store.allSampleAttributionRevisions().count == 2)
    }

    @Test func uncertainArrivalStillAllowsRestoringAnExcludedEndpoint() async throws {
        typealias F = FlightTrajectoryFixtures
        let h = try SampleCorrectionTestSupport.makeHarness(now: F.date(minutes: 4330))
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 75),
            F.sample(3, minutes: 10, east: 150),
            F.sample(4, minutes: 4320, east: 4000),
            F.sample(5, minutes: 4325, east: 4000),
            F.sample(
                6,
                minutes: 4330,
                east: 4000,
            ),
        ]
        try await h.store.perform {
            for sample in samples {
                try await h.store.add(sample: sample)
            }
            try await h.store.addSampleAttributionRevision(.init(
                id: .init(rawValue: UUID()),
                sampleID: samples[0].id,
                updatedAt: F.date(minutes: 30),
                replacementRegions: [],
            ))
        }
        let review = try await h.review()
        let restore = try #require(review.pointCorrections.first { $0.sampleID == samples[0].id })
        #expect(restore.action == .restoreGPS)
        guard case .applied = try await h.coordinator.apply(restore) else {
            Issue
                .record(
                    "Uncertain timing must not prevent withdrawing an existing endpoint exclusion",
                )
            return
        }
        let refreshed = try await h.review()
        #expect(refreshed.pointCorrections.contains { $0.sampleID == samples[0].id } == false)
        #expect(try await h.store.allSamples().count == samples.count)
    }

    @Test func improvedArrivalEvidenceInvalidatesAnUncertainFlightProposal() async throws {
        typealias F = FlightTrajectoryFixtures
        let h = try SampleCorrectionTestSupport.makeHarness(now: F.date(minutes: 4330))
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 75),
            F.sample(3, minutes: 10, east: 150),
            F.sample(4, minutes: 4320, east: 4000),
            F.sample(5, minutes: 4325, east: 4000),
            F.sample(
                6,
                minutes: 4330,
                east: 4000,
            ),
        ]
        try await h.store.perform {
            for sample in samples {
                try await h.store.add(sample: sample)
            }
        }
        let review = try await h.review()
        #expect(review.flight?.progress.arrival?.isTimingUncertain == true)
        let proposal = try #require(review.proposal)
        try await h.store.perform {
            try await h.store.add(sample: F.sample(7, minutes: 15, east: 150))
            try await h.store.add(sample: F.sample(8, minutes: 20, east: 150))
        }
        guard case let .stale(fresh) = try await h.coordinator.apply(proposal) else {
            Issue.record("Changed arrival evidence must require a fresh review")
            return
        }
        #expect(fresh?.flight?.progress.arrival?.isTimingUncertain == false)
        #expect(try await h.store.allSampleAttributionRevisions().isEmpty)
    }

    @Test func pointInclusionAndRestorePreserveRawHistoryAndOtherCorrections() async throws {
        let h = try await SampleCorrectionTestSupport.completedFlight()
        let existing = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: FlightTrajectoryFixtures.sampleID(4),
            updatedAt: FlightTrajectoryFixtures.date(minutes: 149),
            replacementRegions: [],
        )
        try await h.store.perform {
            try await h.store.addSampleAttributionRevision(existing)
        }
        let before = try await h.store.allSamples()
        let review = try await h.review()
        let endpoint = try #require(review.pointCorrections.first {
            $0.sampleID == FlightTrajectoryFixtures.sampleID(5)
        })
        guard case .applied = try await h.coordinator.apply(endpoint) else {
            Issue.record("An unchanged explicit point decision must apply")
            return
        }
        let afterInclusion = try await h.store.allSampleAttributionRevisions()
        #expect(afterInclusion.contains(existing))
        let excluded = afterInclusion.filter { $0.sampleID == endpoint.sampleID }
        #expect(excluded.count == 1)
        #expect(excluded.first?.sampleID == endpoint.sampleID)
        #expect(excluded.first?.replacementRegions == [])
        #expect(try await h.reader.yearReport(for: h.day.year).days.first?.regions == endpoint
            .resultingRegions)
        let updated = try await h.review()
        let restore = try #require(updated.pointCorrections
            .first { $0.sampleID == endpoint.sampleID })
        #expect(restore.action == .restoreGPS)
        guard case .applied = try await h.coordinator.apply(restore) else {
            Issue.record("Restoring the reviewed point must apply")
            return
        }
        let revisions = try await h.store.allSampleAttributionRevisions()
        #expect(revisions.count == 3)
        #expect(revisions.contains(existing))
        let latest = try #require(revisions.max { $0.updatedAt < $1.updatedAt })
        #expect(latest.replacementRegions == nil)
        #expect(latest.updatedAt > excluded[0].updatedAt)
        #expect(try await Set(h.store.allSamples()) == Set(before))
        #expect(try await h.reader.yearReport(for: h.day.year).days.first?.regions == restore
            .resultingRegions)
        guard case .stale = try await h.coordinator.apply(restore) else {
            Issue.record("A stale restore must not append another revision")
            return
        }
        #expect(try await h.store.allSampleAttributionRevisions().count == 3)
    }

    @Test(arguments: InterveningChange.allCases)
    func pointDecisionsRejectChangedEvidence(change: InterveningChange) async throws {
        let h = try await SampleCorrectionTestSupport.completedFlight()
        let review = try await h.review()
        let correction = try #require(review.pointCorrections.first)
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
                        id: .init(rawValue: UUID()),
                        sampleID: correction.sampleID,
                        updatedAt: FlightTrajectoryFixtures.date(minutes: 149),
                        replacementRegions: [],
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
        guard case .stale = try await h.coordinator.apply(correction) else {
            Issue.record("A changed point review must not write")
            return
        }
        #expect(try await h.store.allSampleAttributionRevisions() == before)
    }

    @Test(arguments: [false, true], [false, true])
    func applyingCompletedFlightPreservesPendingFlightOnTheSameDay(
        pendingFirst: Bool,
        separateDevices: Bool,
    ) async throws {
        let trace = FlightTrajectoryFixtures.mixedFlights(
            pendingFirst: pendingFirst,
            separateDevices: separateDevices,
        )
        let h = try SampleCorrectionTestSupport.makeHarness(now: trace.readyAt)
        try await h.store.perform {
            for sample in trace.samples {
                try await h.store.add(sample: sample)
            }
        }
        let proposal = try await h.proposal()
        let before = try await h.reader.dataIssueReads(for: h.day.year).history

        guard case .applied = try await h.coordinator.apply(proposal) else {
            Issue.record("Arrival on one flight must authorize its reviewed edits")
            return
        }

        let revisions = try await h.store.allSampleAttributionRevisions()
        #expect(Set(revisions.map(\.sampleID)) == trace.completedAirborneSampleIDs)
        let after = try await h.reader.dataIssueReads(for: h.day.year).history
        #expect(after.samples.filter { trace.pendingSampleIDs.contains($0.sample.id) }
            == before.samples.filter { trace.pendingSampleIDs.contains($0.sample.id) })
        #expect(after.rawSamples == before.rawSamples)
        let refreshed = try await h.coordinator.review(
            id: proposal.reviewID,
            year: h.day.year,
            primaryRegions: SampleCorrectionTestSupport.attribution.loadedRegions,
            driftThresholdMeters: 1000,
        )
        let review = try #require(refreshed)
        #expect(review.isPending)
        #expect(review.proposal == nil)
        #expect(review.flights.count == 2)
    }

    @Test func applyingJoinedFlightsPreservesSparseLayoverPresence() async throws {
        let trace = FlightTrajectoryFixtures.sparseLayover()
        let attributor = SampleCorrectionTestSupport.SparseLayoverRegions()
        let store = try SwiftDataStore.inMemory()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: attributor,
            aggregator: SampleCorrectionTestSupport.aggregator,
            now: { trace.readyAt },
        )
        try await store.perform {
            for sample in trace.samples {
                try await store.add(sample: sample)
            }
        }
        let day = CalendarDay(
            from: FlightTrajectoryFixtures.start,
            in: SampleCorrectionTestSupport.calendar,
        )
        let review = try await services.corrections.review(
            id: .flightDay(day: day),
            year: day.year,
            primaryRegions: attributor.loadedRegions,
            driftThresholdMeters: 1000,
        )
        let proposal = try #require(review?.proposal)
        #expect(Set(proposal.edits.map(\.sampleID)) == trace.airborneSampleIDs)
        #expect(proposal.resultingRegions == [.california, .canada, .newYork])
        guard case .applied = try await services.corrections.apply(proposal) else {
            Issue.record("The completed flight review must preserve the uncertain layover")
            return
        }
        #expect(try await services.reports.yearReport(for: day.year).days.first?.regions
            == [.california, .canada, .newYork])
        let history = try await services.reports.dataIssueReads(for: day.year).history
        #expect(history.samples.filter { trace.layoverSampleIDs.contains($0.sample.id) }
            .allSatisfy { $0.regions == [.canada] })
        #expect(try await store.allSamples() == trace.samples)
    }

    @Test func recordedFlightBackupAppliesCorrectionsWithoutChangingGroundOrRawSamples(
    ) async throws {
        typealias F = RecordedFlightArchiveFixture
        let archiveURL = try F.makeArchiveFile()
        defer {
            do {
                try FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
            } catch {
                Issue.record(error, "Could not remove the recorded flight test archive")
            }
        }
        let store = try SwiftDataStore.inMemory()
        let regions = F.Regions()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: regions,
            aggregator: DayAggregator(calendar: F.calendar, timeZone: F.calendar.timeZone),
            now: { F.now },
        )
        let imported = try await services.backup.importAndAcknowledgeBackup(
            from: archiveURL,
            strategy: .replace,
        )
        #expect(imported.sampleCount == 52)
        #expect(imported.recordingDeviceCount == 1)
        #expect(try await Set(store.allSamples()) == Set(F.samples))
        #expect(try await Set(store.trackedRegions()) == Set(regions.loadedRegions))
        let before = try await services.reports.dataIssueReads(for: F.day.year)
        #expect(before.history.samples.count == F.samples.count)
        #expect(before.report.days.first { $0.day == F.day }?.regions
            == [.california, .newYork, .canada])

        let review = try await services.corrections.review(
            id: .flightDay(day: F.day),
            year: F.day.year,
            primaryRegions: regions.loadedRegions,
            driftThresholdMeters: 1000,
        )
        let proposal = try #require(review?.proposal)
        let editedIDs = Set(proposal.edits.map(\.sampleID))
        // These five recorded fixes cross the invented middle region with
        // independent cruise observations on both sides of every point.
        let overflightIDs = Set([17, 3, 26, 6, 39].map(FlightTrajectoryFixtures.sampleID))
        #expect(overflightIDs.isSubset(of: editedIDs))
        let departure = try #require(F.samples.first {
            $0.id == FlightTrajectoryFixtures.sampleID(33)
        })
        let arrival = try #require(F.samples.first {
            $0.id == FlightTrajectoryFixtures.sampleID(30)
        })
        let groundIDs = Set(F.samples.filter {
            $0.timestamp <= departure.timestamp || $0.timestamp >= arrival.timestamp
        }.map(\.id))
        #expect(editedIDs.isDisjoint(with: groundIDs))
        #expect(proposal.resultingRegions == [.california, .newYork])
        guard case .applied = try await services.corrections.apply(proposal) else {
            Issue.record("The imported recording's unchanged reviewed correction must apply")
            return
        }

        let after = try await services.reports.dataIssueReads(for: F.day.year)
        #expect(after.report.days.first { $0.day == F.day }?.regions == [.california, .newYork])
        let overflight = after.history.samples.filter { overflightIDs.contains($0.sample.id) }
        #expect(Set(overflight.map(\.sample.id)) == overflightIDs)
        for point in overflight {
            #expect(point.regions.isEmpty)
        }
        #expect(after.history.samples.filter { groundIDs.contains($0.sample.id) }
            == before.history.samples.filter { groundIDs.contains($0.sample.id) })
        #expect(try await Set(store.allSamples()) == Set(F.samples))
        let revisions = try await store.allSampleAttributionRevisions()
        #expect(Set(revisions.map(\.sampleID)) == editedIDs)
        #expect(revisions.count == editedIDs.count)
        #expect(revisions.allSatisfy { $0.replacementRegions == [] })
        #expect(try await services.reports.manualDays(inYear: F.day.year).isEmpty)
        let fresh = try await services.corrections.review(
            id: .flightDay(day: F.day),
            year: F.day.year,
            primaryRegions: regions.loadedRegions,
            driftThresholdMeters: 1000,
        )
        #expect(fresh?.proposal == nil)
        #expect(fresh?.flight?.isPending == false)
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
                        id: .init(rawValue: UUID()),
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
