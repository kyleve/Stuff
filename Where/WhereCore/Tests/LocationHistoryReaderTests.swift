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
            replacementRegions: [.newYork],
        )
        let exclusion = SampleAttributionRevision(
            id: .init(rawValue: FlightTrajectoryFixtures.sampleID(202)),
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
        let reader = LocationHistoryReader(
            store: h.store,
            policy: .foundation,
            geography: HistoryRegionAttribution(),
        )
        let corrected = try await reader.projection(
            in: h.interval,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(corrected.samples.map(\.regions) == [[.newYork], []])
        #expect(corrected.rawSamples == samples)
        #expect(try await h.store.allSamples().sorted { $0.timestamp < $1.timestamp } == samples)

        try await h.coordinator.reset(sampleIDs: Set(samples.map(\.id)))
        // A previously unseen older revision arrives after reset, as with offline sync.
        try await h.store.perform {
            try await h.store.addSampleAttributionRevision(.init(
                id: .init(rawValue: FlightTrajectoryFixtures.sampleID(203)),
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
                    id: .init(rawValue: UUID()),
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
        let projection = try await LocationHistoryReader(
            store: h.store,
            policy: .foundation,
            geography: HistoryRegionAttribution(),
        ).projection(
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

    @Test func recordingSelectionUsesSpecificGeographyBeforePrimaryGrouping() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let first = try [0.0, 600, 1200].map {
            try LocationHistoryReaderTestSupport.sample(seconds: $0, longitude: -122 + $0 / 30000)
        }
        let second = try [0.0, 600, 1200].map {
            try LocationHistoryReaderTestSupport.sample(
                seconds: $0,
                deviceID: LocationHistoryReaderTestSupport.second,
                longitude: -74 + $0 / 30000,
            )
        }
        let later = try LocationHistoryReaderTestSupport.sample(seconds: 7200)
        try await LocationHistoryReaderTestSupport.add(first + second + [later], to: store)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        let original = try await LocationHistoryReaderTestSupport.projection(reader, end: 7201)
        #expect(original.rawSamples == [later])
        #expect(original.samples.map(\.regions) == [[.california]])
        guard case let .recording(selection) = original.contract else {
            Issue.record("Expected recording selection")
            return
        }
        #expect(!selection.issues.isEmpty)
        #expect(selection.policyVersion == RecordingEvidencePolicy.version)
        #expect(original.reportingSamples(primaryRegions: []).map(\.regions) == [[.other]])
        #expect(original.reportingSamples(primaryRegions: [.california])
            .map(\.regions) == [[.california]])
        let changedPrimary = try await reader.projection(
            for: .instants(RecordingAssessmentTestSupport.period(0, 7201)),
            calendar: LocationHistoryReaderTestSupport.calendar,
            attributor: RegionAttributor(for: [.newYork]),
        )
        #expect(changedPrimary == original)
        #expect(try await store.allSamples().count == 7)
    }

    @Test func logicalDateQueryRetainsUTCAdjacentYearAndTheRawAssignment() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let zone = try #require(TimeZone(secondsFromGMT: -3600))
        let sample = try LocationHistoryReaderTestSupport.sample(seconds: 1800, zone: zone)
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        let day = CalendarDay(year: 2000, month: 12, day: 31)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        for hours in [-12, 0, 14] {
            var calendar = LocationHistoryReaderTestSupport.calendar
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: hours * 3600))
            let projection = try await reader.projection(
                for: .days(CalendarDay.yearRange(2000)),
                calendar: calendar,
                attributor: RegionAttributor(for: []),
            )
            #expect(projection.rawSamples == [sample])
            #expect(projection.samples.first?.day == .recording(day))
            #expect(projection.samples.first?.calendarDay(in: calendar) == day)
            let nextYear = try await reader.projection(
                for: .days(CalendarDay.yearRange(2001)),
                calendar: calendar,
                attributor: RegionAttributor(for: []),
            )
            #expect(nextYear.samples.isEmpty)
        }
    }

    @Test func explicitUnknownAndExcludedCorrectionsNeverUseCatalogFallback() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let first = try LocationHistoryReaderTestSupport.sample(seconds: 0)
        let second = try LocationHistoryReaderTestSupport.sample(seconds: 600)
        try await LocationHistoryReaderTestSupport.add([first, second], to: store)
        try await store.perform {
            for sample in [first, second] {
                let regions: Set<Region> = sample.id == first.id ? [.other] : []
                try await store.addSampleAttributionRevision(.init(
                    id: .init(rawValue: UUID()),
                    sampleID: sample.id,
                    updatedAt: RecordingAssessmentTestSupport.time(2000),
                    replacementRegions: regions,
                ))
            }
        }
        let projection = try await LocationHistoryReaderTestSupport.projection(
            LocationHistoryReaderTestSupport.reader(store),
        )
        #expect(projection.rawSamples == [first, second])
        #expect(projection.samples.map(\.regions) == [[.other], []])
        guard case let .recording(selected) = projection.contract else {
            Issue.record("Expected recording selection")
            return
        }
        #expect(selected.contributions.map(\.geography.knownRegions) == [[], []])
        #expect(selected.issues.isEmpty)
    }

    @Test func calendarRecoveryUpdatesEffectiveDayWithoutRewritingRawUnknown() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try LocationHistoryReaderTestSupport.sample(
            seconds: 10,
            assignment: .unresolved,
        )
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        let before = try await LocationHistoryReaderTestSupport.projection(reader)
        #expect(before.samples.isEmpty)
        guard case let .recording(unresolved) = before.contract else {
            Issue.record("Expected recording selection")
            return
        }
        #expect(unresolved.issues.first?.days == .unassigned(known: []))
        let context = try RecordingCalendarContext(timeZone: .gmt, secondsFromGMT: 0)
        try await RecordingChoiceTestSupport.append(.calendar(RecordingControlsTestSupport.calendar(
            900,
            action: .establish(context),
        )), store: store)
        let after = try await LocationHistoryReaderTestSupport.projection(reader)
        #expect(after.rawSamples == [sample])
        #expect(after.samples.first?.day == .recording(.init(year: 2001, month: 1, day: 1)))
        #expect(try await store.allSamples() == [sample])
    }

    @Test func explicitChoiceBypassesIgnoreAndRemovalStillLeavesAnExclusiveGap() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let first = try LocationHistoryReaderTestSupport.sample(seconds: 0)
        let next = try LocationHistoryReaderTestSupport.sample(seconds: 600)
        let other = try LocationHistoryReaderTestSupport.sample(
            seconds: 600,
            deviceID: LocationHistoryReaderTestSupport.second,
            longitude: -74,
        )
        try await LocationHistoryReaderTestSupport.add([first, next, other], to: store)
        try await RecordingChoiceTestSupport.append(
            .ignore(RecordingControlsTestSupport.ignore(910)),
            store: store,
        )
        try await RecordingChoiceTestSupport.append(
            .source(RecordingAssessmentTestSupport.decision(911, end: 1201)),
            store: store,
        )
        let reader = LocationHistoryReaderTestSupport.reader(store)
        #expect(try await LocationHistoryReaderTestSupport.projection(reader).rawSamples == [
            first,
            next,
        ])
        try await store.perform {
            try await store
                .addRecordingDeviceRemoval(RecordingControlSelectionTestSupport.removal(at: 600))
        }
        let removed = try await LocationHistoryReaderTestSupport.projection(reader)
        #expect(removed.rawSamples == [first])
        guard case let .recording(selection) = removed.contract else {
            Issue.record("Expected recording selection")
            return
        }
        #expect(selection.issues.contains {
            $0.problem == .controls(.selectedDeviceRemoved(LocationHistoryReaderTestSupport.first))
        })
        #expect(try await store.allSamples().count == 3)
    }

    @Test func narrowQueryUsesAdjacentMovementBeforeClipping() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let moving = try [0.0, 600, 1200].map {
            try LocationHistoryReaderTestSupport.sample(seconds: $0, longitude: -122 + $0 / 30000)
        }
        let stationary = try [0.0, 600, 1200].map {
            try LocationHistoryReaderTestSupport.sample(
                seconds: $0,
                deviceID: LocationHistoryReaderTestSupport.second,
                longitude: -74,
            )
        }
        try await LocationHistoryReaderTestSupport.add(moving + stationary, to: store)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        let full = try await LocationHistoryReaderTestSupport.projection(reader)
        let narrow = try await LocationHistoryReaderTestSupport.projection(
            reader,
            start: 600,
            end: 601,
        )
        #expect(full.rawSamples == moving)
        #expect(narrow.rawSamples == [moving[1]])
        guard case let .recording(selection) = narrow.contract else {
            Issue.record("Expected recording selection")
            return
        }
        #expect(selection.issues.isEmpty)
        #expect(selection.segments.first?
            .resolution ==
            .automatic(.movingOverStationary(LocationHistoryReaderTestSupport.first)))
    }

    @Test func supportingMajorOneDoesNotActivateAnExistingFoundationDataset() async throws {
        let store = try SwiftDataStore.inMemory()
        let sample = FlightTrajectoryFixtures.sample(990, minutes: 1, east: 0)
        try await store.perform { try await store.add(sample: sample) }
        let reader = LocationHistoryReader(
            store: store,
            policy: .init(current: RecordingEvidencePolicy.version, supportedMajors: [0, 1]),
            geography: HistoryRegionAttribution(),
        )
        let projection = try await reader.projection(
            in: DateInterval(start: sample.timestamp, duration: 1),
            attributor: SampleCorrectionTestSupport.attribution,
        )
        #expect(projection.contract == .foundation)
        #expect(projection.rawSamples == [sample])
        #expect(projection.samples.first?.day == .viewingCalendar)
        #expect(try await store.dataContractMajor() == 0)
    }
}
