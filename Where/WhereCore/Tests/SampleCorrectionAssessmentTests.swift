import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct SampleCorrectionAssessmentTests {
    private typealias F = SampleCorrectionAssessmentFixtures

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
