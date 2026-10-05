import Foundation
import Testing
@testable import WhereCore

struct FlightPointCorrectionAssessmentTests {
    private typealias F = FlightTrajectoryFixtures

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
}
