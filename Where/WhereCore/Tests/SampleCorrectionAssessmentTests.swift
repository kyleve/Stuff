import Foundation
import RegionKit
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

struct SampleCorrectionAssessmentTests {
    private typealias F = SampleCorrectionAssessmentFixtures

    @Test @MainActor func syncedDuplicateRowsApplyOneRevisionPerSample() async throws {
        let samples = FlightTrajectoryFixtures.turningFlight().samples
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        // Distinct synced records can carry the same logical sample identity.
        for sample in samples + samples {
            context.insert(SDLocationSample(value: sample, generationID: .initial))
        }
        try context.save()
        let store = SwiftDataStore(modelContainer: container)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            attributor: SampleCorrectionTestSupport.attribution,
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
            primaryRegions: SampleCorrectionTestSupport.attribution.loadedRegions,
            driftThresholdMeters: 1000,
        )
        let proposal = try #require(review?.proposal)
        try #require(proposal.edits.isEmpty == false)
        #expect(Set(proposal.edits.map(\.sampleID)).count == proposal.edits.count)
        guard case .applied = try await services.corrections.apply(proposal) else {
            Issue.record("Duplicate synced rows must not prevent the reviewed correction")
            return
        }
        let revisions = try await store.allSampleAttributionRevisions()
        #expect(revisions.count == proposal.edits.count)
        #expect(Set(revisions.map(\.sampleID)) == Set(proposal.edits.map(\.sampleID)))
        #expect(try await store.allSamples().count == samples.count * 2)
        #expect(try await services.reports.yearReport(for: day.year).days.first?.regions
            == proposal.resultingRegions)
    }

    @Test(arguments: [false, true])
    func duplicateRowsProduceOneEditPerSample(isFlight: Bool) throws {
        let samples = if isFlight {
            FlightTrajectoryFixtures.turningFlight().samples
        } else {
            [
                F.point(101, minutes: 0, longitude: -0.001),
                F.point(102, minutes: 5, longitude: 0.0005),
                F.point(103, minutes: 10, longitude: -0.001),
            ]
        }
        let attributor: any RegionAttributing = isFlight
            ? SampleCorrectionTestSupport.attribution : F.Boundary()
        let original = try #require(F.reviews(samples, attributor: attributor).first?.proposal)
        for duplicated in [samples + samples, Array((samples + samples).reversed())] {
            let review = try #require(F.reviews(duplicated, attributor: attributor).first)
            let proposal = try #require(review.proposal)
            #expect(proposal.edits == original.edits)
            #expect(proposal.resultingRegions == original.resultingRegions)
            #expect(Set(proposal.edits.map(\.sampleID)).count == proposal.edits.count)
            #expect(review.points.count == duplicated.count)
            #expect(proposal.evidence.history.rawSamples.count == duplicated.count)
        }
    }

    @Test(arguments: [120.0, 24 * 60 + 5, 48 * 60 + 5])
    func conflictingDuplicateRowsRemainUncorrected(conflictMinutes: Double) throws {
        let samples = [
            F.point(101, minutes: 0, longitude: -0.001),
            F.point(102, minutes: 5, longitude: 0.0005),
            F.point(103, minutes: 10, longitude: -0.001),
        ]
        let original = try #require(F.reviews(samples).first?.proposal)
        #expect(original.edits.map(\.sampleID) == [samples[1].id])
        let conflict = F.point(102, minutes: conflictMinutes, longitude: 1)
        let now = conflict.timestamp.addingTimeInterval(60)
        #expect(F.reviews(samples + [conflict], now: now).isEmpty)
        #expect(F.reviews([conflict] + samples, now: now).isEmpty)
    }

    @Test func boundaryCleanupNamesOnlyTheSupportedSampleAndRetainsDistantEvidence() throws {
        let samples = [
            F.point(101, minutes: 0, longitude: -0.001),
            F.point(102, minutes: 5, longitude: 0.0005),
            F.point(103, minutes: 10, longitude: -0.001),
            F.point(104, minutes: 120, longitude: 1),
        ]
        let proposal = try #require(F.reviews(samples).first?.proposal)
        #expect(proposal.edits == [.init(
            sampleID: samples[1].id,
            replacementRegions: [.california],
        )])
        #expect(proposal.resultingRegions == [.california, .other])
    }

    @Test(arguments: [false, true])
    func boundaryNeedsIndependentBracketsOnBothSides(missingBefore: Bool) {
        let bracket = F.point(101, minutes: missingBefore ? 10 : 0, longitude: -0.001)
        let noise = F.point(102, minutes: 5, longitude: 0.0005)
        #expect(F.reviews([bracket, noise]).isEmpty)
    }

    @Test(arguments: [0.0, 11.0])
    func simultaneousOrDistantBracketsDoNotSupportDrift(minutes: Double) {
        let samples = [
            F.point(101, minutes: 20 - minutes, longitude: -0.001),
            F.point(102, minutes: 20, longitude: 0.0005),
            F.point(103, minutes: 20 + minutes, longitude: -0.001),
        ]
        #expect(F.reviews(samples).isEmpty)
    }

    @Test func differentDevicesCannotBracketBoundaryNoise() {
        let samples = [
            F.point(101, minutes: 0, longitude: -0.001, deviceID: nil),
            F.point(102, minutes: 5, longitude: 0.0005),
            F.point(103, minutes: 10, longitude: -0.001, deviceID: nil),
        ]
        #expect(F.reviews(samples).isEmpty)
    }

    @Test func fastTravelAndPoorPositionsDoNotBecomeBoundaryCleanup() {
        let before = F.point(101, minutes: 0, longitude: -1)
        let noise = F.point(102, minutes: 5, longitude: 0.0005)
        let after = F.point(103, minutes: 10, longitude: -1)
        #expect(F.reviews([before, noise, after]).isEmpty)
        let poor = F.point(104, minutes: 5, longitude: 0.0005, accuracy: 251)
        #expect(F.reviews([
            F.point(105, minutes: 0, longitude: -0.001),
            poor,
            F.point(106, minutes: 10, longitude: -0.001),
        ]).isEmpty)
    }

    @Test func nonGPSAndManualAssertionsKeepTheirContributions() throws {
        let samples = [
            F.point(101, minutes: 0, longitude: -0.001),
            F.point(102, minutes: 5, longitude: 0.0005),
            F.point(103, minutes: 10, longitude: -0.001),
            F.point(104, minutes: 6, longitude: 0.0005, source: .manual),
        ]
        let day = CalendarDay(from: samples[0].timestamp, in: SampleCorrectionTestSupport.calendar)
        let manual = DayPresence(day: day, regions: [.newYork])
        let proposal = try #require(F.reviews(samples, manuals: [manual]).first?.proposal)
        #expect(proposal.edits.map(\.sampleID) == [samples[1].id])
        #expect(proposal.resultingRegions == [.california, .newYork, .other])
        #expect(F.reviews(
            samples,
            manuals: [DayPresence(day: day, regions: [.newYork], isAuthoritative: true)],
        ).isEmpty)
    }

    @Test func pendingFlightHoldsAllAutomaticCleanupUntilArrival() throws {
        let trace = FlightTrajectoryFixtures.turningFlight()
        for now in [trace.lastCruiseAt, trace.firstGroundAt] {
            let review = try #require(F.reviews(
                trace.samples.filter { $0.timestamp <= now },
                attributor: SampleCorrectionTestSupport.attribution,
                now: now,
            ).first)
            #expect(review.isPending)
            #expect(review.proposal == nil)
        }
        let ready = try #require(F.reviews(
            trace.samples,
            attributor: SampleCorrectionTestSupport.attribution,
        ).first?.proposal)
        #expect(ready.resultingRegions.contains(.california))
        #expect(ready.resultingRegions.contains(.newYork))
        #expect(ready.resultingRegions.contains(.other)) // Independent departure noise survives.
        #expect(!ready.edits.contains { $0.sampleID == trace.departureNoiseID })
    }

    @Test func historicalSilenceStaysPendingWithoutAnActionableProposal() throws {
        let trace = FlightTrajectoryFixtures.turningFlight()
        let review = try #require(F.reviews(
            trace.samples.filter { $0.timestamp <= trace.lastCruiseAt },
            attributor: SampleCorrectionTestSupport.attribution,
            now: trace.readyAt.addingTimeInterval(90 * 24 * 60 * 60),
        ).first)
        #expect(review.isPending)
        #expect(review.flight?.progress == .awaitingArrival)
        #expect(review.proposal == nil)
    }

    @Test func authoritativeManualKeepsFlightInformational() throws {
        let trace = FlightTrajectoryFixtures.turningFlight()
        let day = CalendarDay(
            from: trace.samples[0].timestamp,
            in: SampleCorrectionTestSupport.calendar,
        )
        let review = try #require(F.reviews(
            trace.samples,
            manuals: [DayPresence(day: day, regions: [.canada], isAuthoritative: true)],
            attributor: SampleCorrectionTestSupport.attribution,
        ).first)
        #expect(review.proposal == nil)
        #expect(review.day.regions == [.canada])
        guard case .completed = review.state
        else { Issue.record("Expected completed informational flight"); return }
    }
}
