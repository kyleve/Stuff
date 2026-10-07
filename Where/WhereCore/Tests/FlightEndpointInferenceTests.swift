import Testing
@testable import WhereCore

struct FlightEndpointInferenceTests {
    private typealias F = FlightTrajectoryFixtures

    @Test func longGapCorroboratesOnlyTheResumedEndpoint() {
        let samples = F.resumedFlight()
        let reason = FlightEndpointInference.reason(
            cruise: Array(samples[3 ... 6]),
            previous: samples[2],
            endpointObservations: [samples[3]],
        )
        guard case let .recordingGap(duration, speed) = reason else {
            Issue.record("Expected long-gap corroboration")
            return
        }
        #expect(duration == 260 * 60)
        #expect(speed > 730 && speed < 750)
    }

    @Test(arguments: [0.0, 149.0, 269.0, -1000.0])
    func stationaryShortOrUnboundedGapsStayUnknown(previousMinutes: Double) {
        let samples = F.resumedFlight()
        let previous = F.sample(20, minutes: previousMinutes, east: 3200)
        #expect(FlightEndpointInference.reason(
            cruise: Array(samples[3 ... 6]),
            previous: previous,
            endpointObservations: [samples[3]],
        ) == nil)
    }

    @Test func shortCruiseAndReversalsDoNotCorroborateAGap() {
        let samples = F.resumedFlight()
        #expect(FlightEndpointInference.reason(
            cruise: Array(samples[3 ... 4]),
            previous: samples[2],
            endpointObservations: [samples[3]],
        ) == nil)
        #expect(FlightEndpointInference.reason(
            cruise: [F.sample(4, minutes: 270, east: 3200), F.sample(5, minutes: 390, east: 1700)],
            previous: samples[2],
            endpointObservations: [samples[3]],
        ) == nil)
    }

    @Test func measuredSpeedCanSupportAnEndpointWithoutEarlierFixes() {
        let samples = F.resumedFlight()
        let measured = F.replacing(samples[3], motion: .init(
            speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 10),
            altitude: nil,
        ))
        #expect(FlightEndpointInference.reason(
            cruise: Array(samples[3 ... 6]),
            previous: nil,
            endpointObservations: [measured],
        ) == .recordedSpeed(lowerBoundKMH: 828))
    }

    @Test func aSlowDuplicateVetoesBothFormsOfCorroboration() {
        let samples = F.resumedFlight()
        let slow = F.replacing(samples[3], motion: .init(
            speed: .init(metersPerSecond: 1, accuracyMetersPerSecond: 1),
            altitude: nil,
        ))
        let fast = F.replacing(samples[3], motion: .init(
            speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 1),
            altitude: nil,
        ))
        #expect(FlightEndpointInference.reason(
            cruise: Array(samples[3 ... 6]),
            previous: samples[2],
            endpointObservations: [
                fast,
                slow,
            ],
        ) == nil)
    }
}
