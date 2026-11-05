import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingChoiceInspectionTests {
    @Test func correctedTransitDayAndManualOverlayRemainDistinctInThePreview() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try LocationHistoryReaderTestSupport.sample(seconds: 0)
        let day = CalendarDay(year: 2001, month: 1, day: 1)
        let manual = DayPresence(day: day, regions: [.newYork], isAuthoritative: true)
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        try await store.perform {
            try await store.setManualDay(manual)
            try await store.addSampleAttributionRevision(.init(
                id: .init(rawValue: UUID()),
                sampleID: sample.id,
                updatedAt: RecordingAssessmentTestSupport.time(1),
                replacementRegions: [],
            ))
        }
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let preview = try await RecordingChoiceInspectionTestSupport.preview(coordinator.inspect(
            RecordingChoiceInspectionTestSupport.request(end: 100),
        ))
        #expect(preview.after.contributions == [DayPresence(day: day, regions: [])])
        #expect(preview.proposal.evidence.manualDays == [manual])
        #expect(preview.tracks.first?.observations.first?.sample == sample)
        #expect(try await coordinator.apply(preview.proposal) == .applied)
        let report = try await LocationHistoryReaderTestSupport.reports(store).yearReport(for: 2001)
        #expect(report.days.first?.regions == [.newYork])
        #expect(try await store.allManualDays() == [manual])
    }

    @Test func returnToAutomaticPreviewReappliesTheHistoricalIgnore() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            LocationHistoryReaderTestSupport.competingTracks(),
            to: store,
        )
        try await RecordingChoiceTestSupport.append(
            .ignore(RecordingControlsTestSupport.ignore(1930)),
            store: store,
        )
        try await RecordingChoiceTestSupport.append(
            .source(RecordingAssessmentTestSupport.decision(1931, end: 1201)),
            store: store,
        )
        let preview = try await RecordingChoiceInspectionTestSupport.preview(
            RecordingChoiceTestSupport.coordinator(store: store).inspect(
                RecordingChoiceInspectionTestSupport.request(action: .automatic),
            ),
        )
        #expect(preview.before.contributions.first?.regions == [.california])
        #expect(preview.after.contributions.first?.regions == [.newYork])
        #expect(preview.after.issues.isEmpty)
        #expect(preview.proposal.decision
            .predecessors == [RecordingAssessmentTestSupport.decisionID(1931)])
    }

    @Test func previewMatchesTheSavedSelectionWithoutWritingDuringInspection() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let controls = RecordingControlStore(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
        )
        let before = try await controls.snapshot()
        let preview = try await RecordingChoiceInspectionTestSupport.preview(coordinator.inspect(
            RecordingChoiceInspectionTestSupport.request(),
        ))
        #expect(preview.before.contributions.isEmpty)
        #expect(preview.before.issues.count == 1)
        #expect(preview.after.contributions == [DayPresence(
            day: CalendarDay(year: 2001, month: 1, day: 1),
            regions: [.california],
        )])
        #expect(preview.after.issues.isEmpty)
        #expect(preview.tracks.count == 2)
        #expect(try await controls.snapshot() == before)
        #expect(try await coordinator.apply(preview.proposal) == .applied)
        let projection = try await LocationHistoryReaderTestSupport.projection(
            LocationHistoryReaderTestSupport.reader(store),
        )
        if case let .recording(selection) = projection.contract {
            #expect(preview.after.selections == [selection])
        } else {
            Issue.record("Expected recording selection")
        }
        #expect(try await Set(store.allSamples()) == Set(samples))
    }

    @Test func previewRetainsExclusiveGapsAndDoesNotIncludeRivalContributions() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [
            LocationHistoryReaderTestSupport.sample(seconds: 0),
            LocationHistoryReaderTestSupport.sample(seconds: 6000),
            LocationHistoryReaderTestSupport.sample(
                seconds: 3000,
                deviceID: RecordingAssessmentTestSupport.second,
                longitude: -74,
            ),
        ]
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let preview = try await RecordingChoiceInspectionTestSupport.preview(
            RecordingChoiceTestSupport.coordinator(store: store).inspect(
                RecordingChoiceInspectionTestSupport.request(end: 6001),
            ),
        )
        let track = try #require(preview.tracks
            .first { $0.deviceID == RecordingAssessmentTestSupport.first })
        #expect(try track.gaps == [RecordingAssessmentTestSupport.period(1, 6000)])
        #expect(preview.after.contributions.first?.regions == [.california])
        #expect(Set(preview.after.selections.flatMap(\.contributions).map(\.deviceID))
            == [RecordingAssessmentTestSupport.first])
    }

    @Test func disjointChoiceScopesDoNotPreviewOrFillTheGapBetweenThem() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [0.0, 50, 100]
            .map { try LocationHistoryReaderTestSupport.sample(seconds: $0) }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        let periods = try [
            RecordingAssessmentTestSupport.period(0, 1),
            RecordingAssessmentTestSupport.period(100, 101),
        ]
        let preview = try await RecordingChoiceInspectionTestSupport.preview(
            RecordingChoiceTestSupport.coordinator(store: store).inspect(.init(
                scope: .periods(periods),
                action: .select(RecordingAssessmentTestSupport.first),
            )),
        )
        #expect(preview.proposal.decision.periods == periods)
        #expect(preview.tracks.first?.availablePeriods == periods)
        #expect(preview.tracks.first?.gaps.isEmpty == true)
        #expect(Set(preview.after.selections.flatMap(\.contributions).map(\.sample.id))
            == [samples[0].id, samples[2].id])
    }

    @Test func unknownCalendarContextRemainsUnresolvedAfterAnExplicitSourceChoice() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            [LocationHistoryReaderTestSupport.sample(seconds: 0, assignment: .unresolved)],
            to: store,
        )
        let preview = try await RecordingChoiceInspectionTestSupport.preview(
            RecordingChoiceTestSupport.coordinator(store: store).inspect(
                RecordingChoiceInspectionTestSupport.request(end: 100),
            ),
        )
        #expect(preview.after.contributions.isEmpty)
        #expect(preview.after.issues.first?.days == .unassigned(known: []))
        #expect(preview.tracks.first?.observations.first?.recordingDay == .unresolved)
    }

    @Test func selectedRemovalRetainsRawTrackButWithholdsItsUnavailableEvidence() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        try await store.perform {
            try await store
                .addRecordingDeviceRemoval(RecordingControlSelectionTestSupport.removal(at: 600))
        }
        let preview = try await RecordingChoiceInspectionTestSupport.preview(
            RecordingChoiceTestSupport.coordinator(store: store).inspect(
                RecordingChoiceInspectionTestSupport.request(),
            ),
        )
        let track = try #require(preview.tracks
            .first { $0.deviceID == RecordingAssessmentTestSupport.first })
        #expect(track.observations.count == 3)
        #expect(try track.availablePeriods == [RecordingAssessmentTestSupport.period(0, 1)])
        #expect(preview.after.issues.isEmpty == false)
        #expect(preview.after.selections.flatMap(\.contributions).map(\.sample.timestamp)
            == [RecordingAssessmentTestSupport.time(0)])
        #expect(try await Set(store.allSamples()) == Set(samples))
    }

    @Test func staleApplyCanPreviewTheReturnedProposalWithoutAdoptingAnotherArrival() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            LocationHistoryReaderTestSupport.competingTracks(),
            to: store,
        )
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let old = try await RecordingChoiceInspectionTestSupport.preview(coordinator.inspect(
            RecordingChoiceInspectionTestSupport.request(),
        ))
        let incoming = try RecordingAssessmentTestSupport.decision(
            1920,
            end: 1201,
            action: .automatic,
        )
        try await RecordingChoiceTestSupport.append(.source(incoming), store: store)
        guard case let .stale(review) = try await coordinator.apply(old.proposal) else {
            Issue.record("Changed evidence must require another review")
            return
        }
        let later = try RecordingAssessmentTestSupport.decision(
            1921,
            end: 1201,
            action: .select(RecordingAssessmentTestSupport.second),
        )
        try await RecordingChoiceTestSupport.append(.source(later), store: store)
        let preview = try await RecordingChoiceInspectionTestSupport
            .preview(coordinator.inspection(of: review))
        #expect(preview.proposal.decision.predecessors == [incoming.id])
        #expect(preview.proposal.decision.id != old.proposal.decision.id)
        #expect(preview.proposal.evidence.controls.sourceChoices.contains(later) == false)
        guard case .stale = try await coordinator.apply(preview.proposal) else {
            Issue.record("A preview must not silently adopt a later predecessor")
            return
        }
    }

    @Test func inspectionPreservesCalendarClarificationAndRejectsAnotherServiceProposal(
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let coordinator = RecordingChoiceTestSupport.coordinator(store: store)
        let inspection = try await coordinator.inspect(.init(
            scope: .recordingDay(
                deviceID: RecordingAssessmentTestSupport.first,
                day: .init(year: 2001, month: 1, day: 1),
            ),
            action: .select(RecordingAssessmentTestSupport.first),
        ))
        guard case let .needsCalendarContext(context) = inspection else {
            Issue.record("A whole-day choice must retain missing context")
            return
        }
        #expect(context.missingPeriods.isEmpty == false)
        let proposal = try await coordinator.review(RecordingChoiceInspectionTestSupport.request())
        let replacement = RecordingChoiceTestSupport.coordinator(store: store)
        await #expect(throws: DataCompatibilityError.concurrentChange) {
            try await replacement.inspection(of: proposal)
        }
    }
}
