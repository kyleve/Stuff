import Foundation
import Testing
import WhereCore

struct FlightTrajectoryGeneratorTests {
    @Test(arguments: FlightTrajectoryGenerator.Profile.allCases)
    func seededJourneysAreRepeatableAndKeepGroundTruth(profile: FlightTrajectoryGenerator.Profile) {
        let first = FlightTrajectoryGenerator.make(profile: profile, seed: 42)
        let second = FlightTrajectoryGenerator.make(profile: profile, seed: 42)
        #expect(first.samples == second.samples)
        #expect(first.groundIDs == second.groundIDs)
        #expect(first.samples.count >= 3)
        #expect(Set(first.samples.map(\.id)).count == first.samples.count)
        #expect(first.groundIDs.isSubset(of: Set(first.samples.map(\.id))))
        #expect(first.samples.allSatisfy {
            (-90 ... 90).contains($0.coordinate.latitude) && (-180 ... 180)
                .contains($0.coordinate.longitude)
        })
    }

    @Test func clusteredObservationErrorsPreserveStationaryJourneyGroundTruth() throws {
        let scenario = FlightTrajectoryGenerator.make(profile: .clusteredDrift, seed: 42)
        let first = try #require(scenario.samples.first)
        let last = try #require(scenario.samples.last)
        #expect(scenario.samples.contains { $0.coordinate.distance(to: first.coordinate) > 14000 })
        #expect(last.coordinate.distance(to: first.coordinate) < 30)
        #expect(scenario.groundIDs == Set(scenario.samples.map(\.id)))
        #expect(scenario.expectedFlights == 0)
    }

    @Test func reducerPreservesTheFailureWithoutKeepingUnnecessarySamples() {
        let samples = FlightTrajectoryGenerator.make(profile: .sparseJet, seed: 1).samples
        let required = samples[2].id
        let reduced = FlightTrajectoryGenerator
            .reduced(samples) { $0.contains { $0.id == required } }
        #expect(reduced.map(\.id) == [required])
    }
}
