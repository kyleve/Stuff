import Foundation
import Testing
@testable import WhereCore

struct FlightGroundInferenceTests {
    private typealias F = FlightTrajectoryFixtures

    @Test func irregularStationaryCallbacksConfirmOnlyAfterTheSparseDuration() {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 16, east: 0.4),
            F.sample(3, minutes: 18, east: 0.8),
            F.sample(4, minutes: 24, east: 1.1),
        ]
        #expect(FlightGroundInference.episodes(
            anchors: Array(samples.prefix(3)),
            observations: Array(samples.prefix(3)),
        ).isEmpty)
        let episode = FlightGroundInference.episodes(anchors: samples, observations: samples).first
        #expect(episode?.start == 0)
        #expect(episode?.confirmation == 3)
    }

    @Test(arguments: [10.0, 20.0, 30.0, 30.01])
    func stationaryGroundRequiresBoundedPositiveObservations(gapMinutes: Double) {
        let samples = (0 ... 2).map { F.sample($0 + 1, minutes: Double($0) * gapMinutes, east: 0) }
        let episodes = FlightGroundInference.episodes(anchors: samples, observations: samples)
        #expect(episodes.isEmpty == (gapMinutes > 30))
    }

    @Test(arguments: [false, true])
    func movingGroundRequiresReportedSpeedAtEveryObservation(hasSpeed: Bool) {
        let motion: LocationMotion? = hasSpeed
            ? .init(speed: .init(metersPerSecond: 8, accuracyMetersPerSecond: 1), altitude: nil) :
            nil
        let samples = (0 ... 4).map {
            F.sample($0 + 1, minutes: Double($0) * 5, east: Double($0) * 2.5, motion: motion)
        }
        let episodes = FlightGroundInference.episodes(anchors: samples, observations: samples)
        #expect(episodes.isEmpty == (hasSpeed == false))
        if hasSpeed { #expect(episodes.first?.confirmation == 4) }
    }

    @Test func aDenseContradictionVetoesSparseDwell() {
        let samples = [
            F.sample(1, minutes: 0, east: 0),
            F.sample(2, minutes: 20, east: 0),
            F.sample(3, minutes: 40, east: 0),
        ]
        let conflict = F.sample(4, minutes: 20.1, east: 100)
        #expect(FlightGroundInference.episodes(
            anchors: samples,
            observations: [samples[0], samples[1], conflict, samples[2]],
        ).isEmpty)
    }

    @Test func coarseGroundAndSilenceRemainUnknown() {
        let samples = (0 ... 2).map { F.sample(
            $0 + 1,
            minutes: Double($0) * 20,
            east: 0,
            accuracy: 251,
        ) }
        #expect(FlightGroundInference.episodes(anchors: samples, observations: samples).isEmpty)
        #expect(FlightGroundInference.episodes(
            anchors: Array(samples.prefix(2)),
            observations: samples,
        ).isEmpty)
    }
}
