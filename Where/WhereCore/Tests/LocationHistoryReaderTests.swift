import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct LocationHistoryReaderTests {
    @Test func correctionsProjectWithoutChangingRawSamplesAndResetWinsLateDelivery() async throws {
        let h = try SampleCorrectionTestSupport.makeHarness()
        let samples = [
            FlightTrajectoryFixtures.sample(101, minutes: 1, east: 0),
            FlightTrajectoryFixtures.sample(102, minutes: 2, east: 0),
        ]
        let override = SampleAttributionRevision(
            id: FlightTrajectoryFixtures.sampleID(201),
            sampleID: samples[0].id,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 3),
            replacementRegions: [.newYork],
        )
        let exclusion = SampleAttributionRevision(
            id: FlightTrajectoryFixtures.sampleID(202),
            sampleID: samples[1].id,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 3),
            replacementRegions: [],
        )
        try await h.store.perform {
            for sample in samples {
                try await h.store.add(sample: sample)
            }
            try await h.store.addSampleAttributionRevision(override)
            try await h.store.addSampleAttributionRevision(exclusion)
        }
        let reader = LocationHistoryReader(store: h.store)
        let corrected = try await reader.projection(
            in: h.interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(corrected.samples.map(\.regions) == [[.newYork], []])
        #expect(corrected.rawSamples == samples)
        #expect(try await reader.samples(in: h.interval) == samples)
        #expect(try await h.store.allSamples().sorted { $0.timestamp < $1.timestamp } == samples)

        try await h.coordinator.reset(sampleIDs: Set(samples.map(\.id)))
        // A previously unseen older revision arrives after reset, as with offline sync.
        try await h.store.perform {
            try await h.store.addSampleAttributionRevision(.init(
                id: FlightTrajectoryFixtures.sampleID(203),
                sampleID: samples[0].id,
                updatedAt: FlightTrajectoryFixtures.date(minutes: 4),
                replacementRegions: [],
            ))
        }
        let restored = try await reader.projection(
            in: h.interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(restored.samples.map(\.regions) == [[.california], [.california]])
        #expect(restored.rawSamples == samples)
        #expect(restored.revisions.count == 5)
    }

    @Test func removalCutoffsPrecedeCorrectionsAndNonGPSAttributionIsUnaffected() async throws {
        let h = try SampleCorrectionTestSupport.makeHarness()
        let before = FlightTrajectoryFixtures.sample(301, minutes: 1, east: 0)
        let removed = FlightTrajectoryFixtures.sample(302, minutes: 5, east: 0)
        let manual = FlightTrajectoryFixtures.sample(303, minutes: 6, east: 0, source: .manual)
        let evidence = FlightTrajectoryFixtures.sample(
            304,
            minutes: 7,
            east: 0,
            source: .evidenceImplied(
                id: FlightTrajectoryFixtures.sampleID(305),
                kind: .boardingPass,
            ),
        )
        let samples = [before, removed, manual, evidence]
        try await h.store.perform {
            for sample in samples {
                try await h.store.add(sample: sample)
                try await h.store.addSampleAttributionRevision(.init(
                    id: UUID(),
                    sampleID: sample.id,
                    updatedAt: FlightTrajectoryFixtures.date(minutes: 10),
                    replacementRegions: [.newYork],
                ))
            }
            try await h.store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: FlightTrajectoryFixtures.device,
                removedAt: FlightTrajectoryFixtures.date(minutes: 5),
                removedByDeviceID: FlightTrajectoryFixtures.device,
            ))
        }
        let projection = try await LocationHistoryReader(store: h.store).projection(
            in: h.interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(projection.rawSamples == [before, manual, evidence])
        #expect(projection.samples.map(\.regions) == [[.newYork], [.california], [.california]])
        #expect(!projection.revisions.contains { $0.sampleID == removed.id })
        #expect(try await h.store.allSamples().count == samples.count)
        #expect(try await h.reader.yearReport(for: h.day.year).days.first?.regions == [
            .newYork,
            .california,
        ])
    }
}
