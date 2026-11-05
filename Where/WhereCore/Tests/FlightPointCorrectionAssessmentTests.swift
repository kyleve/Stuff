import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct FlightPointCorrectionAssessmentTests {
    private typealias F = FlightTrajectoryFixtures

    @Test(.timeLimit(.minutes(2)), arguments: [100, 250, 1000])
    func denseRecordingFlightRetainsEveryPointDecision(sampleCount: Int) async throws {
        let raw = try RecordingFlightTestSupport
            .samples(F.denseFlight(cruiseSampleCount: sampleCount))
        let store = try await RecordingChoiceTestSupport.store()
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .newYork, appearance: nil, order: 0),
            ])
            for sample in raw {
                try await store.add(sample: sample)
            }
        }
        let calendar = SampleCorrectionTestSupport.calendar
        let reports = RecordingFlightTestSupport.reports(
            store,
            catalog: RecordingFlightTestSupport.Geography(),
            calendar: calendar,
        )
        let reads = try await reports.dataIssueReads(for: 2026)
        guard case .recording = reads.history.contract else {
            Issue.record("The scale fixture must exercise recording selection")
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        let reviews = try SampleCorrectionAssessment(
            attributor: reads.correctionAttribution,
            calendar: calendar,
        ).reviews(reads: reads, driftThresholdMeters: 1000, now: F.date(minutes: 640))
        let elapsed = start.duration(to: clock.now)
        print("RECORDING_POINT_REVIEW_SCALE cruise=\(sampleCount) elapsed=\(elapsed)")
        let review = try #require(reviews.first)
        #expect(review.pointCorrections.count == sampleCount + 1)
        let selected = try #require(review.pointCorrections.dropFirst(sampleCount / 2).first)
        let previewStart = clock.now
        let resultingRegions = try selected.resultingRegions
        print(
            "RECORDING_POINT_PREVIEW_SCALE cruise=\(sampleCount) elapsed=\(previewStart.duration(to: clock.now))",
        )
        #expect(resultingRegions == [.newYork])
        for correction in review.pointCorrections.prefix(1) + review.pointCorrections.suffix(1) {
            #expect(try correction.resultingRegions == [.newYork])
        }
        #expect(try await Set(store.allSamples()) == Set(raw))
    }

    @Test func uncertainArrivalOffersOnlySupportedAirborneIdentities() throws {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 75),
            F.sample(3, minutes: 10, east: 150),
            F.sample(4, minutes: 4320, east: 4000),
            F.sample(5, minutes: 4325, east: 4000),
            F.sample(6, minutes: 4330, east: 4000),
        ]
        let reviews = try SampleCorrectionAssessmentFixtures.reviews(
            samples,
            now: samples[5].timestamp,
        )
        let review = try #require(reviews.first { $0.proposal != nil })
        #expect(review.flights.first?.progress.arrival?.isTimingUncertain == true)
        #expect(review.proposal?.edits.map(\.sampleID) == [samples[1].id])
        #expect(review.pointCorrections.map(\.sampleID) == [samples[1].id])
    }

    @Test func completedFlightOffersUncertainEndpointsAsExplicitDecisions() throws {
        let trace = F.turningFlight()
        let review = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples,
            now: trace.readyAt,
        ).first)
        let endpoint = try #require(review.pointCorrections.first { $0.sampleID == F.sampleID(5) })
        #expect(endpoint.action == .includeInFlight)
        #expect(review.proposal?.edits.contains { $0.sampleID == endpoint.sampleID } == false)
        #expect(review.pointCorrections.contains { $0.sampleID == F.sampleID(1) } == false)
        #expect(review.pointCorrections.contains { $0.sampleID == F.sampleID(18) } == false)
    }

    @Test func pendingFlightsManualAssertionsAndConflictingIdentitiesHaveNoActions() throws {
        let trace = F.turningFlight()
        let pending = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples,
            now: trace.lastCruiseAt,
        ).first)
        #expect(pending.pointCorrections.isEmpty)
        let manual = DayPresence(
            day: pending.day.day,
            regions: [.canada],
            isAuthoritative: true,
            audit: nil,
        )
        let authoritative = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples,
            manuals: [manual],
            now: trace.readyAt,
        ).first)
        #expect(authoritative.pointCorrections.isEmpty)
        let conflict = F.sample(5, minutes: 15, east: 6)
        let conflicted = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples + [conflict],
            now: trace.readyAt,
        ).first)
        #expect(conflicted.pointCorrections.contains { $0.sampleID == conflict.id } == false)
    }

    @Test func manualAndOtherDeviceSamplesNeverBecomeFlightActions() throws {
        let trace = F.turningFlight()
        let manual = F.sample(100, minutes: 25, east: 120, source: .manual)
        let other = F.sample(101, minutes: 25, east: 120, deviceID: nil)
        let review = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples + [manual, other],
            now: trace.readyAt,
        ).first)
        #expect(review.pointCorrections
            .contains { $0.sampleID == manual.id || $0.sampleID == other.id } == false)
    }

    @Test(arguments: [false, true], [false, true])
    func mixedReviewsOfferOnlyCompletedFlightPoints(
        pendingFirst: Bool,
        separateDevices: Bool,
    ) throws {
        let trace = F.mixedFlights(pendingFirst: pendingFirst, separateDevices: separateDevices)
        let review = try #require(SampleCorrectionAssessmentFixtures.reviews(
            trace.samples,
            now: trace.readyAt,
        ).first)
        #expect(review.pointCorrections.isEmpty == false)
        #expect(Set(review.pointCorrections.map(\.sampleID))
            .isDisjoint(with: trace.pendingSampleIDs))
        #expect(review.dismissingProposal()?.pointCorrections == review.pointCorrections)
    }

    @Test(arguments: [false, true], [false, true])
    func resultingRegionsMatchAggregationWithDuplicateRowsAndOtherSupport(
        allGPSExcluded: Bool,
        additiveManualDay: Bool,
    ) throws {
        let trace = F.turningFlight()
        let calendar = SampleCorrectionTestSupport.calendar
        let day = CalendarDay(from: F.start, in: calendar)
        let attributor = SampleCorrectionTestSupport.attribution
        var entries = trace.samples.map { sample in
            let regions: Set<Region> = if allGPSExcluded || sample.id == F.sampleID(8) {
                []
            } else if sample.id == F.sampleID(5) {
                [.newYork, .other]
            } else if sample.id == F.sampleID(6) {
                [.canada]
            } else {
                [.california]
            }
            return AttributedLocationSample(sample: sample, regions: regions)
        }
        // All physical copies of one identity change together. Independent
        // manual and remote-device samples keep their existing contributions.
        entries += [entries[4], entries[4], entries[7]]
        entries += [
            AttributedLocationSample(
                sample: F.sample(100, minutes: 25, east: 120, source: .manual),
                regions: [.canada],
            ),
            AttributedLocationSample(
                sample: F.sample(101, minutes: 25, east: 120, deviceID: nil),
                regions: [.other],
            ),
        ]
        let manuals = additiveManualDay ? [DayPresence(
            day: day,
            regions: [.newYork, .europeanUnion],
            isAuthoritative: false,
            audit: nil,
        )] : []
        let corrections = FlightPointCorrectionAssessment(attributor: attributor).corrections(
            day: day,
            entries: entries,
            conflictingSampleIDs: [],
            dataGenerationID: .initial,
            evidence: .init(
                history: LocationHistoryProjection(samples: entries, revisions: []),
                manualDays: manuals,
                primaryRegions: attributor.loadedRegions,
                trackedRegions: attributor.loadedRegions,
                driftThresholdMeters: 1000,
                calendar: calendar,
                flights: FlightTrajectoryAnalyzer().analyze(
                    samples: trace.samples,
                    now: trace.readyAt,
                ),
            ),
        )
        #expect(corrections.isEmpty == false)
        #expect(corrections.count == Set(corrections.map(\.sampleID)).count)
        #expect(corrections.contains { $0.action == .restoreGPS })
        for correction in corrections {
            let corrected = entries.map { entry in
                guard entry.sample.id == correction.sampleID else { return entry }
                return AttributedLocationSample(
                    sample: entry.sample,
                    regions: correction.action == .restoreGPS
                        ? [attributor.region(at: entry.sample.coordinate)] : [],
                )
            }
            let expected = try #require(SampleCorrectionTestSupport.aggregator
                .report(for: day.year, history: corrected, manualDays: manuals)
                .days.first { $0.day == day })
            #expect(try correction.resultingRegions == expected.regions)
        }
        if !allGPSExcluded {
            let soleSupport = try #require(corrections.first { $0.sampleID == F.sampleID(5) })
            #expect(try soleSupport.resultingRegions.contains(.newYork) == additiveManualDay)
            #expect(try soleSupport.resultingRegions.isSuperset(of: [.canada, .other]))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func denseFlightRetainsEveryPointDecision() throws {
        let sampleCount = 10000
        let review = try #require(SampleCorrectionAssessmentFixtures.reviews(
            F.denseFlight(cruiseSampleCount: sampleCount),
            now: F.date(minutes: 640),
        ).first)
        #expect(review.pointCorrections.count == sampleCount + 1)
        let previewsMatch = try review.pointCorrections.allSatisfy {
            try $0.resultingRegions == [.other]
        }
        #expect(previewsMatch)
    }
}
