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
            id: .init(rawValue: FlightTrajectoryFixtures.sampleID(201)),
            sampleID: samples[0].id,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 3),
            changedByDeviceID: SampleCorrectionTestSupport.editingDevice.id,
            replacementRegions: [.newYork],
        )
        let exclusion = SampleAttributionRevision(
            id: .init(rawValue: FlightTrajectoryFixtures.sampleID(202)),
            sampleID: samples[1].id,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 3),
            changedByDeviceID: SampleCorrectionTestSupport.editingDevice.id,
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
                id: .init(rawValue: FlightTrajectoryFixtures.sampleID(203)),
                sampleID: samples[0].id,
                updatedAt: FlightTrajectoryFixtures.date(minutes: 4),
                changedByDeviceID: SampleCorrectionTestSupport.editingDevice.id,
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
        let resets = restored.revisions.filter { $0.replacementRegions == nil }
        #expect(Set(resets.map(\.sampleID)) == Set(samples.map(\.id)))
        #expect(Set(resets.map(\.changedByDeviceID)) ==
            [SampleCorrectionTestSupport.editingDevice.id])
    }

    @Test func correctionRetainsBothOriginsWhenEditorRemovalAndProfileArriveSeparately(
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        let reader = LocationHistoryReader(store: store)
        let editor = SampleCorrectionTestSupport.editingDevice
        let sample = FlightTrajectoryFixtures.sample(401, minutes: 1, east: 0)
        let revision = SampleAttributionRevision(
            id: .init(rawValue: FlightTrajectoryFixtures.sampleID(402)),
            sampleID: sample.id,
            updatedAt: FlightTrajectoryFixtures.date(minutes: 2),
            changedByDeviceID: editor.id,
            replacementRegions: [.newYork],
        )
        let interval = DateInterval(start: FlightTrajectoryFixtures.start, end: revision.updatedAt)
        try await store.perform { try await store.addSampleAttributionRevision(revision) }
        #expect(try await store.allSampleAttributionRevisions() == [revision])
        #expect(try await reader.samples(in: interval).isEmpty)

        try await store.perform { try await store.add(sample: sample) }
        let corrected = try await reader.projection(
            in: interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(corrected.rawSamples == [sample])
        #expect(corrected.revisions == [revision])
        #expect(corrected.samples.map(\.regions) == [[.newYork]])

        // An editor's removal must never cut off the recorder's GPS.
        try await store.perform {
            try await store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: FlightTrajectoryFixtures.sampleID(403)),
                deviceID: editor.id,
                removedAt: FlightTrajectoryFixtures.start,
                removedByDeviceID: FlightTrajectoryFixtures.device,
            ))
        }
        let afterRemoval = try await reader.projection(
            in: interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(afterRemoval == corrected)

        try await store.perform {
            try await store.addRecordingDeviceProfile(.init(
                id: editor.id,
                systemName: editor.systemName,
                kind: editor.kind,
                registeredAt: FlightTrajectoryFixtures.start,
                registrationGenerationID: .initial,
            ))
        }
        let afterProfile = try await reader.projection(
            in: interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(afterProfile == corrected)
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
                    id: .init(rawValue: UUID()),
                    sampleID: sample.id,
                    updatedAt: FlightTrajectoryFixtures.date(minutes: 10),
                    changedByDeviceID: SampleCorrectionTestSupport.editingDevice.id,
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
