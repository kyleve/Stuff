import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct SampleAttributionResetTests {
    @Test(arguments: [false, true])
    func resetSuppressesDelayedCorrectionsWithoutAnActiveReplacement(
        repeated: Bool,
    ) async throws {
        let h = try SampleCorrectionTestSupport.makeHarness()
        let sample = FlightTrajectoryFixtures.sample(101, minutes: 1, east: 0)
        try await h.store.perform { try await h.store.add(sample: sample) }
        if repeated {
            try await SampleAttributionReset.write(
                sampleIDs: [sample.id],
                store: h.store,
                now: FlightTrajectoryFixtures.date(minutes: 10),
            )
        }

        let resetAt = FlightTrajectoryFixtures.date(minutes: 30)
        try await SampleAttributionReset.write(
            sampleIDs: [sample.id],
            store: h.store,
            now: resetAt,
        )
        // The other device's edit predates this reset but, on a repeated reset,
        // is newer than the tombstone we already knew about.
        try await h.store.perform {
            try await h.store.addSampleAttributionRevision(.init(
                id: UUID(),
                sampleID: sample.id,
                updatedAt: FlightTrajectoryFixtures.date(minutes: 20),
                replacementRegions: [.newYork],
            ))
        }

        let projection = try await LocationHistoryReader(store: h.store).projection(
            in: h.interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(projection.rawSamples == [sample])
        #expect(projection.samples.map(\.regions) == [[.california]])
        let revisions = try await h.store.allSampleAttributionRevisions()
        #expect(revisions.count(where: { $0.replacementRegions == nil }) == (repeated ? 2 : 1))
        let winner = try #require(revisions.last)
        #expect(winner.updatedAt == resetAt)
        #expect(winner.replacementRegions == nil)
    }

    @Test(arguments: [false, true])
    func resetAdvancesPastAKnownRevisionWhenItsClockIsAhead(alreadyReset: Bool) async throws {
        let store = try SwiftDataStore.inMemory()
        let sampleID = UUID()
        let prior = SampleAttributionRevision(
            id: UUID(),
            sampleID: sampleID,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 30),
            replacementRegions: alreadyReset ? nil : [.newYork],
        )
        try await store.perform { try await store.addSampleAttributionRevision(prior) }

        try await SampleAttributionReset.write(
            sampleIDs: [sampleID],
            store: store,
            now: FlightTrajectoryFixtures.date(minutes: 20),
        )

        let revisions = try await store.allSampleAttributionRevisions()
        #expect(revisions.count == 2)
        let winner = try #require(revisions.last)
        #expect(winner.updatedAt > prior.updatedAt)
        #expect(winner.replacementRegions == nil)
    }
}
