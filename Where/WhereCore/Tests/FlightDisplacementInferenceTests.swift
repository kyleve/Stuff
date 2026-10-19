import Foundation
import Testing
@testable import WhereCore

private typealias F = FlightTrajectoryFixtures

struct FlightDisplacementInferenceTests {
    @Test(arguments: [5.0, 5 + 1.0 / 60, 20.0, 60.0, 270.0, 800.0])
    func recognizesShortRegionalAndLongHaulDisplacements(minutes: Double) {
        let distanceKM = minutes * 15
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 5 + minutes, east: distanceKM),
            F.sample(4, minutes: 10 + minutes, east: distanceKM),
        ]
        #expect(supports(samples))
    }

    @Test func distanceAndTimeEstablishTravelWithoutMotionSensors() {
        let samples = F.sparseFlight()
        #expect(supports(samples))
        #expect(samples.allSatisfy { $0.motion == nil })
    }

    @Test(arguments: [10.0, 700.0, 1200.0])
    func implausiblyFastSlowOrUnboundedTravelRemainsUnknown(minutes: Double) {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 5 + minutes, east: 4000),
            F.sample(4, minutes: 10 + minutes, east: 4000),
        ]
        #expect(supports(samples) == false)
    }

    @Test(arguments: [0.5, 31.0])
    func duplicateCallbacksAndDistantSupportCannotConfirmEndpoints(minutes: Double) {
        let samples = [
            F.sample(1, minutes: 5 - minutes, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 275, east: 4000),
            F.sample(4, minutes: 275 + minutes, east: 4000),
        ]
        #expect(supports(samples) == false)
    }

    @Test(arguments: [1.0, 5 - 1.0 / 60])
    func briefDisplacementsNeedObservedCruiseInstead(minutes: Double) {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 5 + minutes, east: minutes * 15),
            F.sample(4, minutes: 10 + minutes, east: minutes * 15),
        ]
        #expect(supports(samples) == false)
    }

    @Test(arguments: [37.6, 124.9])
    func shortTravelWithinUncertaintyAdjustedSpeedLimitsQualifies(distanceKM: Double) {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 10, east: distanceKM),
            F.sample(4, minutes: 15, east: distanceKM),
        ]
        #expect(supports(samples))
    }

    @Test(arguments: [37.4, 125.1])
    func shortTravelOutsideSpeedLimitsRemainsUnknown(distanceKM: Double) {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 10, east: distanceKM),
            F.sample(4, minutes: 15, east: distanceKM),
        ]
        #expect(supports(samples) == false)
    }

    @Test func oppositeEndpointsCannotCorroborateAlternatingJumps() {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 50),
            F.sample(3, minutes: 10, east: 0),
            F.sample(4, minutes: 15, east: 50),
        ]
        #expect(supports(samples) == false)
    }

    @Test func supportMustFavorItsOwnEndpointBeyondPositionalUncertainty() {
        let samples = [
            F.sample(1, minutes: 0, east: 24.9, accuracy: 1000),
            F.sample(2, minutes: 5, east: 0, accuracy: 1000),
            F.sample(3, minutes: 10, east: 50, accuracy: 1000),
            F.sample(4, minutes: 15, east: 50, accuracy: 1000),
        ]
        #expect(supports(samples) == false)
    }

    @Test func positionalUncertaintyMustClearTheSpeedThreshold() {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0, accuracy: 250),
            F.sample(3, minutes: 65, east: 450.1, accuracy: 250),
            F.sample(4, minutes: 70, east: 450.1),
        ]
        #expect(supports(samples) == false)
    }

    @Test func anIsolatedJumpAndReturnDoesNotEstablishTravel() {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 5, east: 0),
            F.sample(3, minutes: 275, east: 4000),
            F.sample(4, minutes: 280, east: 0),
        ]
        #expect(supports(samples) == false)
    }

    @Test func conflictingDenseCallbacksVetoOtherwiseCorroboratedTravel() {
        let samples = F.sparseFlight()
        let conflict = F.sample(100, minutes: 275 + 5.0 / 60, east: 0)
        #expect(FlightDisplacementInference.supportsFlight(
            from: samples[1],
            to: samples[2],
            previous: samples[0],
            next: samples[3],
            observations: samples + [conflict],
        ) == false)
    }

    private func supports(_ samples: [LocationSample]) -> Bool {
        FlightDisplacementInference.supportsFlight(
            from: samples[1],
            to: samples[2],
            previous: samples[0],
            next: samples[3],
            observations: samples,
        )
    }
}
